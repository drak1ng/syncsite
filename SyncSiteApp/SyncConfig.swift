import Foundation

struct SyncConfig: Equatable {
    var host = ""
    var user = ""
    var password = ""
    var root = "/public_html"

    static func load(from projectURL: URL) -> SyncConfig {
        let url = projectURL.appendingPathComponent(".syncsite")
        guard
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return SyncConfig()
        }

        var config = SyncConfig()

        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))

            switch key {
            case "FTP_HOST":
                config.host = value
            case "FTP_USER":
                config.user = value
            case "FTP_PASSWORD":
                config.password = value
            case "FTP_ROOT":
                config.root = value
            default:
                continue
            }
        }

        return config
    }

    func save(to projectURL: URL) throws {
        let content = """
        FTP_HOST=\(Self.quote(host))
        FTP_USER=\(Self.quote(user))
        FTP_PASSWORD=\(Self.quote(password))
        FTP_ROOT=\(Self.quote(root))
        """

        let url = projectURL.appendingPathComponent(".syncsite")
        try content.appending("\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    var isComplete: Bool {
        !host.isEmpty && !user.isEmpty && !password.isEmpty && !root.isEmpty
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        return "\"\(escaped)\""
    }

    private static func unquote(_ value: String) -> String {
        var result = value

        if result.hasPrefix("\""), result.hasSuffix("\""), result.count >= 2 {
            result.removeFirst()
            result.removeLast()
        }

        return result
            .replacingOccurrences(of: "\\`", with: "`")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
