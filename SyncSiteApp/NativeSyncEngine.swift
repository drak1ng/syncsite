import CryptoKit
import Foundation

struct FileFingerprint: Codable, Equatable {
    let path: String
    let size: Int64
    let modifiedAt: TimeInterval
    let addedAt: TimeInterval
    let parentFolderModifiedAt: TimeInterval
    let sha256: String

    static func == (lhs: FileFingerprint, rhs: FileFingerprint) -> Bool {
        lhs.path == rhs.path &&
            lhs.size == rhs.size &&
            lhs.modifiedAt == rhs.modifiedAt &&
            lhs.sha256 == rhs.sha256
    }

    enum CodingKeys: String, CodingKey {
        case path
        case size
        case modifiedAt
        case addedAt
        case parentFolderModifiedAt
        case sha256
    }

    init(path: String, size: Int64, modifiedAt: TimeInterval, addedAt: TimeInterval, parentFolderModifiedAt: TimeInterval, sha256: String) {
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.addedAt = addedAt
        self.parentFolderModifiedAt = parentFolderModifiedAt
        self.sha256 = sha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        size = try container.decode(Int64.self, forKey: .size)
        modifiedAt = try container.decode(TimeInterval.self, forKey: .modifiedAt)
        addedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .addedAt) ?? modifiedAt
        parentFolderModifiedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .parentFolderModifiedAt) ?? modifiedAt
        sha256 = try container.decode(String.self, forKey: .sha256)
    }
}

struct SiteSnapshot: Codable {
    let files: [String: FileFingerprint]
    let createdAt: Date
}

struct FileChange: Identifiable, Equatable {
    enum Kind: String {
        case upload = "Enviar"
        case delete = "Remover"
    }

    var id: String { "\(kind.rawValue):\(path)" }
    let kind: Kind
    let path: String
    let size: Int64

    var folderPath: String {
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent().path
        return folder == "." ? "" : folder
    }
}

struct SyncProgress: Equatable {
    var fraction: Double = 0
    var title = "Aguardando"
    var detail = ""
    var eta = ""
}

struct SyncSummary {
    let uploaded: Int
    let deleted: Int
    let bytesUploaded: Int64
}

enum NativeSyncEngine {
    static func testConnection(config: SyncConfig) async throws -> String {
        let result = try await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--list-only",
            "--user",
            "\(config.user):\(config.password)",
            ftpURL(config: config, relativePath: "", trailingSlash: true)
        ])

        return result.output
    }

    static func changes(for site: Site, config: SyncConfig, modifiedAfter: Date? = nil) throws -> [FileChange] {
        let current = try scan(projectURL: site.projectURL)
        if let modifiedAfter {
            return current.files.values
                .filter { Date(timeIntervalSince1970: max($0.modifiedAt, $0.addedAt, $0.parentFolderModifiedAt)) >= modifiedAfter }
                .map { FileChange(kind: .upload, path: $0.path, size: $0.size) }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        let previous = loadSnapshot(for: site)?.files ?? [:]
        var changes: [FileChange] = []

        for (path, fingerprint) in current.files {
            if previous[path] != fingerprint {
                changes.append(FileChange(kind: .upload, path: path, size: fingerprint.size))
            }
        }

        for (path, fingerprint) in previous where current.files[path] == nil {
            changes.append(FileChange(kind: .delete, path: path, size: fingerprint.size))
        }

        return changes.sorted { lhs, rhs in
            if lhs.kind.rawValue == rhs.kind.rawValue {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }

            return lhs.kind == .upload
        }
    }

    static func createBaseline(for site: Site) throws {
        let snapshot = try scan(projectURL: site.projectURL)
        try saveSnapshot(snapshot, for: site)
    }

    static func sync(
        site: Site,
        config: SyncConfig,
        modifiedAfter: Date? = nil,
        progress: @escaping @MainActor (SyncProgress) -> Void
    ) async throws -> SyncSummary {
        let changes = try changes(for: site, config: config, modifiedAfter: modifiedAfter)
        return try await sync(site: site, config: config, changes: changes, progress: progress)
    }

    static func sync(
        site: Site,
        config: SyncConfig,
        changes: [FileChange],
        progress: @escaping @MainActor (SyncProgress) -> Void,
        completedChange: @escaping @MainActor (FileChange) -> Void = { _ in }
    ) async throws -> SyncSummary {
        let current = try scan(projectURL: site.projectURL)
        let uploadChanges = changes.filter { $0.kind == .upload }
        let deleteChanges = changes.filter { $0.kind == .delete }
        let totalBytes = max(uploadChanges.reduce(Int64(0)) { $0 + $1.size }, 1)
        let startedAt = Date()
        var completedBytes: Int64 = 0
        var uploaded = 0
        var deleted = 0

        await progress(SyncProgress(
            fraction: 0,
            title: "Preparando envio",
            detail: "\(changes.count) alterações encontradas",
            eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes)
        ))

        for (index, change) in uploadChanges.enumerated() {
            try Task.checkCancellation()
            await progress(SyncProgress(
                fraction: Double(completedBytes) / Double(totalBytes),
                title: "Enviando arquivo \(index + 1)/\(uploadChanges.count)",
                detail: change.path,
                eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes)
            ))

            let fileURL = site.projectURL.appendingPathComponent(change.path)
            do {
                try await upload(fileURL: fileURL, relativePath: change.path, config: config)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SyncError.fileFailed(change: change, action: "enviar", detail: error.localizedDescription)
            }

            try Task.checkCancellation()
            completedBytes += change.size
            uploaded += 1
            try markChangeSynced(change, site: site)
            await completedChange(change)

            await progress(SyncProgress(
                fraction: Double(completedBytes) / Double(totalBytes),
                title: "Upload em andamento",
                detail: "\(uploaded)/\(uploadChanges.count) arquivos enviados",
                eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes)
            ))
        }

        for (index, change) in deleteChanges.enumerated() {
            try Task.checkCancellation()
            await progress(SyncProgress(
                fraction: Double(completedBytes) / Double(totalBytes),
                title: "Removendo arquivo remoto \(index + 1)/\(deleteChanges.count)",
                detail: change.path,
                eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes)
            ))

            do {
                try await delete(relativePath: change.path, config: config)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw SyncError.fileFailed(change: change, action: "remover", detail: error.localizedDescription)
            }

            try Task.checkCancellation()
            deleted += 1
            try markChangeSynced(change, site: site)
            await completedChange(change)
        }

        try saveSnapshot(current, for: site)

        await progress(SyncProgress(fraction: 1, title: "Sincronização concluída", detail: "\(uploaded) enviados, \(deleted) removidos", eta: "Concluído"))

        return SyncSummary(uploaded: uploaded, deleted: deleted, bytesUploaded: completedBytes)
    }

    private static func scan(projectURL: URL) throws -> SiteSnapshot {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return SiteSnapshot(files: [:], createdAt: Date())
        }

        var files: [String: FileFingerprint] = [:]
        var folderModifiedAtCache: [String: TimeInterval] = [:]

        for case let fileURL as URL in enumerator {
            let relativePath = relativePath(for: fileURL, baseURL: projectURL)

            if shouldSkip(relativePath: relativePath) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let parentFolderModifiedAt = newestParentFolderModifiedAt(
                for: fileURL,
                baseURL: projectURL,
                cache: &folderModifiedAtCache
            )

            files[relativePath] = FileFingerprint(
                path: relativePath,
                size: Int64(values.fileSize ?? data.count),
                modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                addedAt: values.addedToDirectoryDate?.timeIntervalSince1970 ?? 0,
                parentFolderModifiedAt: parentFolderModifiedAt,
                sha256: hash
            )
        }

        return SiteSnapshot(files: files, createdAt: Date())
    }

    private static func fingerprint(for fileURL: URL, relativePath: String, projectURL: URL) throws -> FileFingerprint {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey]
        let values = try fileURL.resourceValues(forKeys: keys)
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var folderModifiedAtCache: [String: TimeInterval] = [:]

        return FileFingerprint(
            path: relativePath,
            size: Int64(values.fileSize ?? data.count),
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            addedAt: values.addedToDirectoryDate?.timeIntervalSince1970 ?? 0,
            parentFolderModifiedAt: newestParentFolderModifiedAt(
                for: fileURL,
                baseURL: projectURL,
                cache: &folderModifiedAtCache
            ),
            sha256: hash
        )
    }

    private static func markChangeSynced(_ change: FileChange, site: Site) throws {
        let existingSnapshot = loadSnapshot(for: site) ?? SiteSnapshot(files: [:], createdAt: Date())
        var files = existingSnapshot.files

        switch change.kind {
        case .upload:
            let fileURL = site.projectURL.appendingPathComponent(change.path)
            files[change.path] = try fingerprint(for: fileURL, relativePath: change.path, projectURL: site.projectURL)
        case .delete:
            files.removeValue(forKey: change.path)
        }

        try saveSnapshot(SiteSnapshot(files: files, createdAt: existingSnapshot.createdAt), for: site)
    }

    private static func shouldSkip(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        let excluded = [".git", ".DS_Store", ".syncsite", "syncsite", "git-ftp"]
        return components.contains { excluded.contains($0) }
    }

    private static func newestParentFolderModifiedAt(
        for fileURL: URL,
        baseURL: URL,
        cache: inout [String: TimeInterval]
    ) -> TimeInterval {
        let basePath = baseURL.standardizedFileURL.path
        var folderURL = fileURL.deletingLastPathComponent().standardizedFileURL
        var newest: TimeInterval = 0

        while folderURL.path.hasPrefix(basePath), folderURL.path != basePath {
            let folderPath = folderURL.path
            let modifiedAt: TimeInterval

            if let cached = cache[folderPath] {
                modifiedAt = cached
            } else {
                let values = try? folderURL.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
                modifiedAt = max(
                    values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    values?.addedToDirectoryDate?.timeIntervalSince1970 ?? 0
                )
                cache[folderPath] = modifiedAt
            }

            newest = max(newest, modifiedAt)
            folderURL.deleteLastPathComponent()
        }

        return newest
    }

    private static func relativePath(for fileURL: URL, baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(basePath.count + 1))
    }

    private static func upload(fileURL: URL, relativePath: String, config: SyncConfig) async throws {
        try await ensureRemoteDirectories(for: relativePath, config: config)

        _ = try await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--ftp-method",
            "nocwd",
            "--upload-file",
            fileURL.path,
            "--user",
            "\(config.user):\(config.password)",
            ftpURL(config: config, relativePath: relativePath)
        ])
    }

    private static func ensureRemoteDirectories(for relativePath: String, config: SyncConfig) async throws {
        let directories = remoteDirectoryPaths(for: relativePath, config: config)
        guard !directories.isEmpty else {
            return
        }

        var arguments = [
            "--silent",
            "--show-error",
            "--user",
            "\(config.user):\(config.password)"
        ]

        for directory in directories {
            arguments.append("--quote")
            arguments.append("*MKD \(directory)")
        }

        arguments.append(ftpURL(config: config, relativePath: "", trailingSlash: true))
        _ = try await runCurl(arguments: arguments)
    }

    private static func delete(relativePath: String, config: SyncConfig) async throws {
        let commandPath = remoteRoot(config.root) + "/" + relativePath
        _ = try await runCurl(arguments: [
            "--silent",
            "--show-error",
            "--fail",
            "--user",
            "\(config.user):\(config.password)",
            "--quote",
            "*DELE \(commandPath)",
            ftpURL(config: config, relativePath: "", trailingSlash: true)
        ])
    }

    private static func ftpURL(config: SyncConfig, relativePath: String, trailingSlash: Bool = false) -> String {
        var path = remoteRoot(config.root)
        if !relativePath.isEmpty {
            path += "/" + relativePath.split(separator: "/").map { encodePathComponent(String($0)) }.joined(separator: "/")
        }

        if trailingSlash, !path.hasSuffix("/") {
            path += "/"
        }

        return "ftp://\(config.host)\(path)"
    }

    private static func remoteRoot(_ root: String) -> String {
        let trimmed = root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : "/" + trimmed
    }

    private static func remoteDirectoryPaths(for relativePath: String, config: SyncConfig) -> [String] {
        var components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else {
            return []
        }

        components.removeLast()
        let root = remoteRoot(config.root)
        var current = root
        var directories: [String] = []

        for component in components {
            current += "/" + component
            directories.append(current)
        }

        return directories
    }

    private static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func progressInfo(startedAt: Date, completedBytes: Int64, totalBytes: Int64) -> String {
        guard completedBytes > 0 else {
            return "Calculando"
        }

        let elapsed = max(Date().timeIntervalSince(startedAt), 0.1)
        let bytesPerSecond = Double(completedBytes) / elapsed
        guard bytesPerSecond > 0 else {
            return "Calculando"
        }

        let remaining = Double(max(totalBytes - completedBytes, 0)) / bytesPerSecond
        return "\(formattedDuration(seconds: Int(ceil(remaining)))) restantes - \(formattedSpeed(bytesPerSecond: bytesPerSecond))"
    }

    private static func formattedDuration(seconds totalSeconds: Int) -> String {
        guard totalSeconds > 0 else {
            return "Menos de 1s"
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))min \(String(format: "%02d", seconds))s"
        }

        if minutes > 0 {
            return "\(minutes)min \(String(format: "%02d", seconds))s"
        }

        return "\(seconds)s"
    }

    private static func formattedSpeed(bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true

        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    private static func loadSnapshot(for site: Site) -> SiteSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(for: site)) else {
            return nil
        }

        return try? JSONDecoder().decode(SiteSnapshot.self, from: data)
    }

    private static func saveSnapshot(_ snapshot: SiteSnapshot, for site: Site) throws {
        let url = snapshotURL(for: site)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static func snapshotURL(for site: Site) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL
            .appendingPathComponent("SyncSite", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
            .appendingPathComponent("\(site.id.uuidString).json")
    }

    private static func runCurl(arguments: [String]) async throws -> CommandResult {
        let processBox = CommandProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let outputPipe = Pipe()
                let collector = OutputCollector()

                processBox.set(process)
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                        return
                    }
                    collector.append(text)
                }

                process.terminationHandler = { process in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    let output = collector.value()
                    if processBox.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: CommandResult(status: process.terminationStatus, output: output))
                    } else {
                        continuation.resume(throwing: SyncError.commandFailed(output))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }
}

private final class CommandProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = cancelled
        lock.unlock()

        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

enum SyncError: LocalizedError {
    case commandFailed(String)
    case fileFailed(change: FileChange, action: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .fileFailed(let change, let action, let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Falha ao \(action) o arquivo:\n\(change.path)\n\nDetalhes:\n\(trimmed.isEmpty ? "O servidor não retornou detalhes do erro." : trimmed)"
        }
    }

    var failedChange: FileChange? {
        switch self {
        case .commandFailed:
            return nil
        case .fileFailed(let change, _, _):
            return change
        }
    }
}
