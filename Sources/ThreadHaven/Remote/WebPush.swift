import CryptoKit
import Foundation

enum WebPush {
    enum PushError: Error, Equatable {
        case invalidKey
        case payloadTooLarge
        case invalidEndpoint
    }

    enum Delivery: Equatable {
        case delivered
        case gone
        case failed(Int)
    }

    static let recordSize: UInt32 = 4096
    static let maxPlaintext = 3_800

    static let allowedHostSuffixes = [
        "push.apple.com",
        "fcm.googleapis.com",
        "push.services.mozilla.com",
        "notify.windows.com",
    ]

    static func isAllowedEndpoint(_ string: String) -> Bool {
        guard string.utf8.count <= 2_048,
              let components = URLComponents(string: string),
              components.scheme == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), !host.isEmpty,
              components.url != nil else { return false }
        return allowedHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func validate(_ subscription: PushSubscription) -> Bool {
        guard isAllowedEndpoint(subscription.endpoint),
              let key = Data(base64URL: subscription.p256dh), key.count == 65,
              (try? P256.KeyAgreement.PublicKey(x963Representation: key)) != nil,
              let auth = Data(base64URL: subscription.auth), auth.count == 16 else { return false }
        return true
    }

    static func encrypt(
        _ plaintext: Data,
        userAgentPublicKey: Data,
        authSecret: Data,
        senderKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey(),
        salt: Data = .random(count: 16)
    ) throws -> Data {
        guard plaintext.count <= maxPlaintext else { throw PushError.payloadTooLarge }
        guard authSecret.count == 16, salt.count == 16,
              let receiver = try? P256.KeyAgreement.PublicKey(x963Representation: userAgentPublicKey) else {
            throw PushError.invalidKey
        }
        let senderPublic = senderKey.publicKey.x963Representation
        let shared = try senderKey.sharedSecretFromKeyAgreement(with: receiver)
        let keyInfo = Data("WebPush: info".utf8) + Data([0]) + userAgentPublicKey + senderPublic
        let ikm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: authSecret, sharedInfo: keyInfo, outputByteCount: 32)
        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: aes128gcm".utf8) + Data([0]), outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: nonce".utf8) + Data([0]), outputByteCount: 12)
        let record = plaintext + Data([2])
        let sealed = try AES.GCM.seal(record, using: cek, nonce: AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }))
        var header = salt
        withUnsafeBytes(of: recordSize.bigEndian) { header.append(contentsOf: $0) }
        header.append(UInt8(senderPublic.count))
        header.append(senderPublic)
        return header + sealed.ciphertext + sealed.tag
    }

    static func vapidAuthorization(endpoint: String, key: P256.Signing.PrivateKey, subject: String, expiry: Date) throws -> String {
        guard let components = URLComponents(string: endpoint), let scheme = components.scheme, let host = components.host else {
            throw PushError.invalidEndpoint
        }
        let audience = scheme + "://" + host + (components.port.map { ":\($0)" } ?? "")
        let header = try JSONSerialization.data(withJSONObject: ["typ": "JWT", "alg": "ES256"], options: [.sortedKeys])
        let claims = try JSONSerialization.data(
            withJSONObject: ["aud": audience, "exp": Int(expiry.timeIntervalSince1970), "sub": subject],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let signingInput = header.base64URLEncoded + "." + claims.base64URLEncoded
        let signature = try key.signature(for: Data(signingInput.utf8))
        let jwt = signingInput + "." + signature.rawRepresentation.base64URLEncoded
        return "vapid t=\(jwt), k=\(key.publicKey.x963Representation.base64URLEncoded)"
    }

    static func request(
        payload: Data,
        subscription: PushSubscription,
        vapidKey: P256.Signing.PrivateKey,
        subject: String,
        now: Date = .now
    ) throws -> URLRequest {
        guard validate(subscription), let url = URL(string: subscription.endpoint),
              let receiver = Data(base64URL: subscription.p256dh),
              let auth = Data(base64URL: subscription.auth) else { throw PushError.invalidEndpoint }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = try encrypt(payload, userAgentPublicKey: receiver, authSecret: auth)
        request.setValue("aes128gcm", forHTTPHeaderField: "Content-Encoding")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "TTL")
        request.setValue("high", forHTTPHeaderField: "Urgency")
        request.setValue(
            try vapidAuthorization(endpoint: subscription.endpoint, key: vapidKey, subject: subject, expiry: now.addingTimeInterval(12 * 3600)),
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static func send(_ request: URLRequest) async -> Delivery {
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300: return .delivered
            case 404, 410: return .gone
            default: return .failed(status)
            }
        } catch {
            return .failed(0)
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
