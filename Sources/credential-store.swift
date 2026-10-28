import Foundation

enum CredentialError: LocalizedError {
    case keychainUnavailable(status: Int32)
    case unreadablePayload
    case missingAccessToken
    case expired

    var errorDescription: String? {
        switch self {
        case .keychainUnavailable(let status):
            "Could not read Keychain (security exit code \(status))"
        case .unreadablePayload:
            "Could not parse Claude credentials"
        case .missingAccessToken:
            "No Claude CLI session — sign in with `claude` in a terminal"
        case .expired:
            "Session expired — run Claude CLI once to refresh it"
        }
    }
}

struct ClaudeCredential: Sendable {
    let accessToken: String
    let expiresAt: Date
}

enum CredentialStore {
    static let keychainService = "Claude Code-credentials"
    static let securityToolPath = "/usr/bin/security"

    static func loadCredential() throws -> ClaudeCredential {
        let raw = try readKeychainSecret()
        let payload = try decodePayload(raw)
        guard let token = payload["accessToken"] as? String, !token.isEmpty else {
            throw CredentialError.missingAccessToken
        }
        let expiresAtMilliseconds = payload["expiresAt"] as? Double ?? 0
        let credential = ClaudeCredential(accessToken: token, expiresAt: Date(timeIntervalSince1970: expiresAtMilliseconds / 1000))
        guard credential.expiresAt > Date() else {
            throw CredentialError.expired
        }
        return credential
    }

    private static func readKeychainSecret() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: securityToolPath)
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CredentialError.keychainUnavailable(status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodePayload(_ raw: String) throws -> [String: Any] {
        let text = isHexEncoded(raw) ? decodeHex(raw) : raw
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw CredentialError.unreadablePayload
        }
        let json = Data(text[start...end].utf8)
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CredentialError.unreadablePayload
        }
        return root["claudeAiOauth"] as? [String: Any] ?? root
    }

    private static func isHexEncoded(_ value: String) -> Bool {
        !value.isEmpty && value.count.isMultiple(of: 2) && value.allSatisfy(\.isHexDigit)
    }

    private static func decodeHex(_ value: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            if let byte = UInt8(value[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
