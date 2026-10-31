import Foundation

enum Tailscale {
    struct ServeState: Equatable, Sendable {
        var served = false
        var funneled = false
    }

    static let appCLI = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    static func findCLI(
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let pathDirectories = (environmentPath ?? "").split(separator: ":").map(String.init)
        let candidates = [appCLI]
            + (pathDirectories + ["/opt/homebrew/bin", "/usr/local/bin"]).map { $0 + "/tailscale" }
        return candidates.first { $0.hasPrefix("/") && isExecutable($0) }
    }

    static func serveCommand(port: UInt16) -> String {
        "tailscale serve --bg --https=443 http://127.0.0.1:\(port)"
    }

    static func dnsName(fromStatusJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = object["Self"] as? [String: Any],
              var name = me["DNSName"] as? String else { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        name = name.lowercased()
        guard (1...253).contains(name.utf8.count), name.contains("."),
              name.utf8.allSatisfy({ ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 46 }),
              !name.hasPrefix("."), !name.hasPrefix("-") else { return nil }
        return name
    }

    static func serveState(fromStatusJSON data: Data, port: UInt16) -> ServeState {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ServeState() }
        var state = ServeState()
        let funnels = (object["AllowFunnel"] as? [String: Any] ?? [:]).filter { ($0.value as? Bool) == true }.map(\.key)
        let targets = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
        let proxiesToUs = { (proxy: String) -> Bool in
            let stripped = proxy.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https+insecure://", with: "").replacingOccurrences(of: "https://", with: "")
            let hostPort = stripped.split(separator: "/", maxSplits: 1).first.map(String.init) ?? stripped
            return targets.contains(hostPort) || hostPort == String(port)
        }
        for (hostPort, value) in object["Web"] as? [String: Any] ?? [:] {
            guard let handlers = (value as? [String: Any])?["Handlers"] as? [String: Any] else { continue }
            let matches = handlers.values.contains { handler in
                ((handler as? [String: Any])?["Proxy"] as? String).map(proxiesToUs) ?? false
            }
            guard matches else { continue }
            state.served = true
            if funnels.contains(hostPort) { state.funneled = true }
        }
        for (listenPort, value) in object["TCP"] as? [String: Any] ?? [:] {
            guard let forward = (value as? [String: Any])?["TCPForward"] as? String, targets.contains(forward) else { continue }
            state.served = true
            if funnels.contains(where: { $0.hasSuffix(":" + listenPort) }) { state.funneled = true }
        }
        return state
    }

    static func run(_ cli: String, _ arguments: [String], timeout: TimeInterval = 5) -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        var output = Data()
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : nil
    }

    struct Probe: Sendable, Equatable {
        var cliFound = false
        var dnsName: String?
        var serve = ServeState()
        var funnelUnknown = false
    }

    static func probe(port: UInt16) -> Probe {
        guard let cli = findCLI() else { return Probe() }
        var probe = Probe(cliFound: true)
        probe.dnsName = run(cli, ["status", "--json"]).flatMap(dnsName(fromStatusJSON:))
        if let data = run(cli, ["funnel", "status", "--json"]) {
            probe.serve = serveState(fromStatusJSON: data, port: port)
        } else {
            probe.funnelUnknown = true
        }
        return probe
    }
}
