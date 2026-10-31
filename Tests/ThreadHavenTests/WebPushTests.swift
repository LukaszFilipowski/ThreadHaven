import CryptoKit
import Foundation
import Testing
@testable import ThreadHaven

struct WebPushTests {
    private func data(_ base64URL: String) throws -> Data {
        try #require(Data(base64URL: base64URL))
    }

    @Test func encryptsTheRFC8291Example() throws {
        let plaintext = Data("When I grow up, I want to be a watermelon".utf8)
        let sender = try P256.KeyAgreement.PrivateKey(rawRepresentation: data("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"))
        #expect(sender.publicKey.x963Representation.base64URLEncoded
            == "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8")
        let body = try WebPush.encrypt(
            plaintext,
            userAgentPublicKey: data("BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"),
            authSecret: data("BTBZMqHH6r4Tts7J_aSIgg"),
            senderKey: sender,
            salt: data("DGv6ra1nlYgDCS1FRnbzlw")
        )
        #expect(body.base64URLEncoded == "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN")
    }

    @Test func receiverCanDecryptWhatWasEncrypted() throws {
        let receiver = P256.KeyAgreement.PrivateKey()
        let auth = Data.random(count: 16)
        let message = Data(#"{"title":"Example chat","body":"Your turn"}"#.utf8)
        let body = try WebPush.encrypt(message, userAgentPublicKey: receiver.publicKey.x963Representation, authSecret: auth)

        let salt = body.prefix(16)
        #expect(body[16..<20] == Data([0, 0, 0x10, 0]))
        let keyLength = Int(body[20])
        let senderPublic = body[21..<(21 + keyLength)]
        let sealed = body[(21 + keyLength)...]

        let shared = try receiver.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: senderPublic))
        let info = Data("WebPush: info".utf8) + Data([0]) + receiver.publicKey.x963Representation + senderPublic
        let ikm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: auth, sharedInfo: info, outputByteCount: 32)
        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: aes128gcm\0".utf8), outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: nonce\0".utf8), outputByteCount: 12)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }),
            ciphertext: sealed.dropLast(16),
            tag: sealed.suffix(16)
        )
        let opened = try AES.GCM.open(box, using: cek)
        #expect(opened == message + Data([2]))
    }

    @Test func rejectsOversizedPayloadAndBadKeys() {
        let receiver = P256.KeyAgreement.PrivateKey().publicKey.x963Representation
        #expect(throws: WebPush.PushError.payloadTooLarge) {
            try WebPush.encrypt(Data(count: 5_000), userAgentPublicKey: receiver, authSecret: Data(count: 16))
        }
        #expect(throws: WebPush.PushError.invalidKey) {
            try WebPush.encrypt(Data("x".utf8), userAgentPublicKey: Data(count: 65), authSecret: Data(count: 16))
        }
        #expect(throws: WebPush.PushError.invalidKey) {
            try WebPush.encrypt(Data("x".utf8), userAgentPublicKey: receiver, authSecret: Data(count: 8))
        }
    }

    @Test func vapidTokenIsAValidES256JWT() throws {
        let key = P256.Signing.PrivateKey()
        let header = try WebPush.vapidAuthorization(
            endpoint: "https://push.example.invalid/send/abc?x=1",
            key: key,
            subject: "https://example.invalid",
            expiry: Date(timeIntervalSince1970: 1_900_000_000)
        )
        #expect(header.hasPrefix("vapid t="))
        let parts = header.dropFirst("vapid t=".count).components(separatedBy: ", k=")
        #expect(parts.count == 2)
        #expect(parts[1] == key.publicKey.x963Representation.base64URLEncoded)
        let jwt = parts[0].split(separator: ".").map(String.init)
        #expect(jwt.count == 3)
        let claims = try #require(JSONSerialization.jsonObject(with: data(jwt[1])) as? [String: Any])
        #expect(claims["aud"] as? String == "https://push.example.invalid")
        #expect(claims["exp"] as? Int == 1_900_000_000)
        #expect(claims["sub"] as? String == "https://example.invalid")
        let headerJSON = try #require(JSONSerialization.jsonObject(with: data(jwt[0])) as? [String: String])
        #expect(headerJSON == ["typ": "JWT", "alg": "ES256"])
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: data(jwt[2]))
        #expect(key.publicKey.isValidSignature(signature, for: Data((jwt[0] + "." + jwt[1]).utf8)))
    }

    @Test func onlyKnownPushServicesAreAllowed() {
        #expect(WebPush.isAllowedEndpoint("https://web.push.apple.com/QGv1"))
        #expect(WebPush.isAllowedEndpoint("https://fcm.googleapis.com/fcm/send/abc"))
        #expect(WebPush.isAllowedEndpoint("https://updates.push.services.mozilla.com/wpush/v2/abc"))
        #expect(!WebPush.isAllowedEndpoint("http://web.push.apple.com/QGv1"))
        #expect(!WebPush.isAllowedEndpoint("https://evilpush.apple.com.example.invalid/x"))
        #expect(!WebPush.isAllowedEndpoint("https://notpush.apple.com/x"))
        #expect(!WebPush.isAllowedEndpoint("https://127.0.0.1/x"))
        #expect(!WebPush.isAllowedEndpoint("https://user:pass@web.push.apple.com/x"))
        #expect(!WebPush.isAllowedEndpoint("https://web.push.apple.com:8443/x"))
        #expect(!WebPush.isAllowedEndpoint("file:///etc/hosts"))
    }

    @Test func validatesSubscriptionKeys() {
        let key = P256.KeyAgreement.PrivateKey().publicKey.x963Representation.base64URLEncoded
        let auth = Data.random(count: 16).base64URLEncoded
        #expect(WebPush.validate(PushSubscription(endpoint: "https://web.push.apple.com/x", p256dh: key, auth: auth)))
        #expect(!WebPush.validate(PushSubscription(endpoint: "https://web.push.apple.com/x", p256dh: "AAAA", auth: auth)))
        #expect(!WebPush.validate(PushSubscription(endpoint: "https://web.push.apple.com/x", p256dh: key, auth: "AAAA")))
        #expect(!WebPush.validate(PushSubscription(endpoint: "https://example.invalid/x", p256dh: key, auth: auth)))
    }

    @Test func base64URLRoundTrips() throws {
        for count in 0..<40 {
            let value = Data.random(count: count)
            #expect(try data(value.base64URLEncoded) == value)
        }
        #expect(Data(base64URL: "a+b/") == nil)
        #expect(Data(base64URL: "ab c") == nil)
    }
}
