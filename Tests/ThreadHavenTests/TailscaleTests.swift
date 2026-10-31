import Foundation
import Testing
@testable import ThreadHaven

struct TailscaleTests {
    @Test func readsTheTailnetNameOfThisMac() {
        let json = #"{"Version":"1.90.0","Self":{"DNSName":"Example-Mac.example-tailnet.ts.net.","HostName":"Example Mac"}}"#
        #expect(Tailscale.dnsName(fromStatusJSON: Data(json.utf8)) == "example-mac.example-tailnet.ts.net")
    }

    @Test func readsTheLoginOfThisMacsUser() {
        let json = #"{"Self":{"DNSName":"example-mac.example-tailnet.ts.net.","UserID":12345},"User":{"12345":{"ID":12345,"LoginName":"Alice@Example.invalid"},"999":{"ID":999,"LoginName":"bob@example.invalid"}}}"#
        #expect(Tailscale.ownLogin(fromStatusJSON: Data(json.utf8)) == "alice@example.invalid")
        let tagged = #"{"Self":{"UserID":1},"User":{"1":{"LoginName":"tagged-devices"}}}"#
        #expect(Tailscale.ownLogin(fromStatusJSON: Data(tagged.utf8)) == nil)
        #expect(Tailscale.ownLogin(fromStatusJSON: Data(#"{"Self":{}}"#.utf8)) == nil)
    }

    @Test func rejectsMissingOrOddNames() {
        #expect(Tailscale.dnsName(fromStatusJSON: Data(#"{"Self":{}}"#.utf8)) == nil)
        #expect(Tailscale.dnsName(fromStatusJSON: Data(#"{"Self":{"DNSName":""}}"#.utf8)) == nil)
        #expect(Tailscale.dnsName(fromStatusJSON: Data(#"{"Self":{"DNSName":"host/evil.ts.net."}}"#.utf8)) == nil)
        #expect(Tailscale.dnsName(fromStatusJSON: Data(#"{"Self":{"DNSName":"a b.ts.net"}}"#.utf8)) == nil)
        #expect(Tailscale.dnsName(fromStatusJSON: Data("not json".utf8)) == nil)
    }

    @Test func detectsServeAndFunnelForOurPort() {
        let served = #"{"TCP":{"443":{"HTTPS":true}},"Web":{"example-mac.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:50123"}}}}}"#
        #expect(Tailscale.serveState(fromStatusJSON: Data(served.utf8), port: 50123) == .init(served: true, funneled: false))
        #expect(Tailscale.serveState(fromStatusJSON: Data(served.utf8), port: 50124) == .init(served: false, funneled: false))

        let funneled = #"{"TCP":{"443":{"HTTPS":true}},"Web":{"example-mac.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://localhost:50123"}}}},"AllowFunnel":{"example-mac.example-tailnet.ts.net:443":true}}"#
        #expect(Tailscale.serveState(fromStatusJSON: Data(funneled.utf8), port: 50123) == .init(served: true, funneled: true))

        let otherFunnel = #"{"Web":{"example-mac.example-tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:50123"}}},"example-mac.example-tailnet.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3000"}}}},"AllowFunnel":{"example-mac.example-tailnet.ts.net:8443":true}}"#
        #expect(Tailscale.serveState(fromStatusJSON: Data(otherFunnel.utf8), port: 50123) == .init(served: true, funneled: false))

        let tcpFunnel = #"{"TCP":{"10000":{"TCPForward":"127.0.0.1:50123"}},"AllowFunnel":{"example-mac.example-tailnet.ts.net:10000":true}}"#
        #expect(Tailscale.serveState(fromStatusJSON: Data(tcpFunnel.utf8), port: 50123) == .init(served: true, funneled: true))

        #expect(Tailscale.serveState(fromStatusJSON: Data("{}".utf8), port: 50123) == .init())
    }

    @Test func findsTheCLI() {
        let found = Tailscale.findCLI(environmentPath: "/usr/bin:/opt/example/bin", isExecutable: { $0 == "/opt/example/bin/tailscale" })
        #expect(found == "/opt/example/bin/tailscale")
        let app = Tailscale.findCLI(environmentPath: "/usr/bin", isExecutable: { _ in true })
        #expect(app == Tailscale.appCLI)
        #expect(Tailscale.findCLI(environmentPath: "relative/bin", isExecutable: { $0.hasPrefix("relative") }) == nil)
        #expect(Tailscale.findCLI(environmentPath: nil, isExecutable: { _ in false }) == nil)
    }

    @Test func buildsTheServeCommand() {
        #expect(Tailscale.serveCommand(port: 50123) == "tailscale serve --bg --https=443 http://127.0.0.1:50123")
    }
}
