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

enum SyncOperationPhase: String {
    case idle
    case testing
    case preparing
    case uploading
    case deleting
    case completed
    case cancelled
    case failed
}

struct SyncProgress: Equatable {
    var fraction: Double = 0
    var title = "Aguardando"
    var detail = ""
    var eta = ""
    var phase: SyncOperationPhase = .idle
    var currentItem = 0
    var totalItems = 0
}

struct SyncSummary {
    let uploaded: Int
    let deleted: Int
    let bytesUploaded: Int64
}

struct BackupSummary {
    let downloaded: Int
}

struct BackupFileProgress: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let totalBytes: Int64?
    var downloadedBytes: Int64
    var startedAt: Date
}

private struct BackupDownloadOutcome {
    let file: RemoteFile
    let errorMessage: String?
    let hitConnectionLimit: Bool
}

private final class BackupProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: BackupFileProgress] = [:]
    private var lastPublished = Date.distantPast
    private let callback: @MainActor ([BackupFileProgress]) -> Void

    init(callback: @escaping @MainActor ([BackupFileProgress]) -> Void) {
        self.callback = callback
    }

    func start(_ file: RemoteFile) {
        lock.lock()
        files[file.relativePath] = BackupFileProgress(path: file.relativePath, totalBytes: file.size, downloadedBytes: 0, startedAt: Date())
        publishIfNeeded(force: true)
        lock.unlock()
    }

    func update(_ path: String, bytes: Int64) {
        lock.lock()
        if var file = files[path] {
            file.downloadedBytes = bytes
            files[path] = file
        }
        publishIfNeeded(force: false)
        lock.unlock()
    }

    func finish(_ path: String) {
        lock.lock()
        files[path] = nil
        publishIfNeeded(force: true)
        lock.unlock()
    }

    private func publishIfNeeded(force: Bool) {
        guard force || Date().timeIntervalSince(lastPublished) >= 0.12 else { return }
        lastPublished = Date()
        let snapshot = files.values.sorted { $0.startedAt > $1.startedAt }
        Task { @MainActor in callback(snapshot) }
    }
}

actor UploadProgressState {
    private var uploaded = 0
    private var completedBytes: Int64 = 0

    func markUploaded(bytes: Int64) -> (uploaded: Int, completedBytes: Int64) {
        uploaded += 1
        completedBytes += bytes
        return (uploaded, completedBytes)
    }

    func snapshot() -> (uploaded: Int, completedBytes: Int64) {
        (uploaded, completedBytes)
    }
}

enum NativeSyncEngine {
    static func testConnection(config: SyncConfig) async throws -> String {
        try await Task.detached {
            let client = try FTPClient(config: config)
            defer { client.close() }
            return try client.verifyRoot()
        }.value
    }

    static func changes(for site: Site, config: SyncConfig, modifiedAfter: Date? = nil) throws -> [FileChange] {
        let previous = loadSnapshot(for: site)?.files ?? [:]
        let current = try scan(projectURL: site.projectURL, previousFiles: previous)
        if let modifiedAfter {
            return current.files.values
                .filter { Date(timeIntervalSince1970: max($0.modifiedAt, $0.addedAt, $0.parentFolderModifiedAt)) >= modifiedAfter }
                .map { FileChange(kind: .upload, path: $0.path, size: $0.size) }
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

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

    static func changesAsync(for site: Site, config: SyncConfig, modifiedAfter: Date? = nil) async throws -> [FileChange] {
        let worker = Task.detached {
            try Task.checkCancellation()
            return try changes(for: site, config: config, modifiedAfter: modifiedAfter)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func createBaseline(for site: Site) throws {
        let previous = loadSnapshot(for: site)?.files ?? [:]
        let snapshot = try scan(projectURL: site.projectURL, previousFiles: previous)
        try saveSnapshot(snapshot, for: site)
    }

    static func backup(
        site: Site,
        config: SyncConfig,
        progress: @escaping @MainActor (SyncProgress) -> Void,
        activeFiles: @escaping @MainActor ([BackupFileProgress]) -> Void
    ) async throws -> BackupSummary {
        let worker = Task.detached {
            let reporter = BackupProgressReporter(callback: activeFiles)
            let root = remoteRoot(config.root)
            await progress(SyncProgress(title: "Listando arquivos do FTP", detail: "Preparando backup", phase: .preparing))
            let listingClient = try FTPClient(config: config)
            let files = try listingClient.recursiveFiles(at: root)
            listingClient.close()

            var pending = files
            var completed = 0
            var concurrency = min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 4)

            while !pending.isEmpty {
                try Task.checkCancellation()
                let batch = Array(pending.prefix(concurrency))
                pending.removeFirst(batch.count)
                var retry: [RemoteFile] = []

                await withTaskGroup(of: BackupDownloadOutcome.self) { group in
                    for remoteFile in batch {
                        group.addTask {
                            do {
                                try Task.checkCancellation()
                                let client = try FTPClient(config: config)
                                defer { client.close() }
                                reporter.start(remoteFile)
                                defer { reporter.finish(remoteFile.relativePath) }
                                try client.download(remotePath: remoteFile.remotePath, to: site.projectURL.appendingPathComponent(remoteFile.relativePath)) { bytes in
                                    reporter.update(remoteFile.relativePath, bytes: bytes)
                                }
                                return BackupDownloadOutcome(file: remoteFile, errorMessage: nil, hitConnectionLimit: false)
                            } catch {
                                let message = error.localizedDescription
                                return BackupDownloadOutcome(file: remoteFile, errorMessage: message, hitConnectionLimit: isConnectionLimit(message))
                            }
                        }
                    }

                    for await outcome in group {
                        if let errorMessage = outcome.errorMessage {
                            if outcome.hitConnectionLimit, concurrency > 1 {
                                retry.append(outcome.file)
                                continue
                            }
                            pending.removeAll()
                            retry.removeAll()
                            await progress(SyncProgress(title: "Backup interrompido", detail: outcome.file.relativePath, eta: errorMessage, phase: .failed))
                            continue
                        }

                        completed += 1
                        await progress(SyncProgress(
                            fraction: Double(completed) / Double(max(files.count, 1)),
                            title: "Baixando backup FTP",
                            detail: outcome.file.relativePath,
                            eta: "\(completed)/\(files.count) arquivos baixados · \(concurrency) conexões",
                            phase: .uploading,
                            currentItem: completed,
                            totalItems: files.count
                        ))
                    }
                }

                try Task.checkCancellation()
                if completed + pending.count + retry.count < files.count {
                    throw FTPClientError.connectionFailed("Não foi possível baixar um ou mais arquivos do backup.")
                }
                if !retry.isEmpty {
                    concurrency -= 1
                    pending.insert(contentsOf: retry, at: 0)
                }
            }

            let previous = loadSnapshot(for: site)?.files ?? [:]
            let snapshot = try scan(projectURL: site.projectURL, previousFiles: previous, hashChangedFiles: false)
            try saveSnapshot(snapshot, for: site)
            await progress(SyncProgress(fraction: 1, title: "Backup concluído", detail: "\(files.count) arquivos baixados", eta: "Concluído", phase: .completed, currentItem: files.count, totalItems: files.count))
            return BackupSummary(downloaded: files.count)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func isConnectionLimit(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("421") || lowercased.contains("too many") || lowercased.contains("max connections") || lowercased.contains("connection limit")
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
        let previous = loadSnapshot(for: site)?.files ?? [:]
        let current = try scan(projectURL: site.projectURL, previousFiles: previous)
        let uploadChanges = changes.filter { $0.kind == .upload }
        let deleteChanges = changes.filter { $0.kind == .delete }
        let totalBytes = max(uploadChanges.reduce(Int64(0)) { $0 + $1.size }, 1)
        let startedAt = Date()
        var completedBytes: Int64 = 0
        var uploaded = 0
        var deleted = 0
        let totalItems = changes.count

        await progress(SyncProgress(
            fraction: 0,
            title: "Preparando envio",
            detail: "\(changes.count) alterações encontradas",
            eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes),
            phase: .preparing,
            currentItem: 0,
            totalItems: totalItems
        ))

        if !uploadChanges.isEmpty {
            try await ensureRemoteDirectories(for: uploadChanges.map(\.path), config: config)
        }

        let uploadConcurrency = min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 3), 6)
        let uploadState = UploadProgressState()
        let uploadGroups = partition(uploadChanges, workerCount: uploadConcurrency)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for workerChanges in uploadGroups where !workerChanges.isEmpty {
                group.addTask {
                    let client = try FTPClient(config: config)
                    defer { client.close() }

                    for change in workerChanges {
                        try Task.checkCancellation()
                        let fileURL = site.projectURL.appendingPathComponent(change.path)

                        do {
                            try client.upload(fileURL: fileURL, remotePath: ftpCommandPath(config: config, relativePath: change.path))
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            throw SyncError.fileFailed(change: change, action: "enviar", detail: error.localizedDescription)
                        }

                        let state = await uploadState.markUploaded(bytes: change.size)
                        await completedChange(change)

                        await progress(SyncProgress(
                            fraction: Double(state.completedBytes) / Double(totalBytes),
                            title: "Enviando arquivos",
                            detail: "\(state.uploaded)/\(uploadChanges.count) arquivos enviados",
                            eta: progressInfo(startedAt: startedAt, completedBytes: state.completedBytes, totalBytes: totalBytes),
                            phase: .uploading,
                            currentItem: state.uploaded + deleted,
                            totalItems: totalItems
                        ))
                    }
                }
            }

            try await group.waitForAll()
        }

        let uploadedState = await uploadState.snapshot()
        completedBytes = uploadedState.completedBytes
        uploaded = uploadedState.uploaded

        if !uploadChanges.isEmpty {
            await progress(SyncProgress(
                fraction: Double(completedBytes) / Double(totalBytes),
                title: "Enviando arquivos",
                detail: "\(uploaded)/\(uploadChanges.count) arquivos enviados",
                eta: progressInfo(startedAt: startedAt, completedBytes: completedBytes, totalBytes: totalBytes),
                phase: .uploading,
                currentItem: uploaded + deleted,
                totalItems: totalItems
            ))
        }

        let deleteClient: FTPClient?
        if deleteChanges.isEmpty {
            deleteClient = nil
        } else {
            deleteClient = try FTPClient(config: config)
        }
        defer { deleteClient?.close() }

        for (index, change) in deleteChanges.enumerated() {
            try Task.checkCancellation()
            await progress(SyncProgress(
                fraction: Double(completedBytes) / Double(totalBytes),
                title: "Removendo arquivos",
                detail: change.path,
                eta: "\(index + 1)/\(deleteChanges.count) removidos",
                phase: .deleting,
                currentItem: uploaded + deleted + 1,
                totalItems: totalItems
            ))

            do {
                try deleteClient?.delete(remotePath: ftpCommandPath(config: config, relativePath: change.path))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Remote deletes are best-effort. If the server refuses the delete
                // because the file is already missing, blocked, or stale, the local
                // snapshot still needs to advance so the queue cannot get stuck.
            }

            try Task.checkCancellation()
            deleted += 1
            await completedChange(change)
        }

        try saveSnapshot(current, for: site)

        await progress(SyncProgress(fraction: 1, title: "Sincronização concluída", detail: "\(uploaded) enviados, \(deleted) removidos", eta: "Concluído", phase: .completed, currentItem: totalItems, totalItems: totalItems))

        return SyncSummary(uploaded: uploaded, deleted: deleted, bytesUploaded: completedBytes)
    }

    private static func scan(projectURL: URL, previousFiles: [String: FileFingerprint], hashChangedFiles: Bool = true) throws -> SiteSnapshot {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: projectURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return SiteSnapshot(files: [:], createdAt: Date())
        }

        var files: [String: FileFingerprint] = [:]
        var folderModifiedAtCache: [String: TimeInterval] = [:]

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
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

            let size = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let parentFolderModifiedAt = newestParentFolderModifiedAt(
                for: fileURL,
                baseURL: projectURL,
                cache: &folderModifiedAtCache
            )
            let addedAt = values.addedToDirectoryDate?.timeIntervalSince1970 ?? 0

            // Igual ao índice do Git, metadados inalterados evitam reler e hashear o arquivo.
            let hash: String
            if let previous = previousFiles[relativePath],
               previous.size == size,
               previous.modifiedAt == modifiedAt {
                hash = previous.sha256
            } else if hashChangedFiles {
                hash = try contentHash(for: fileURL)
            } else {
                hash = "metadata:\(relativePath):\(size):\(modifiedAt)"
            }

            files[relativePath] = FileFingerprint(
                path: relativePath,
                size: size,
                modifiedAt: modifiedAt,
                addedAt: addedAt,
                parentFolderModifiedAt: parentFolderModifiedAt,
                sha256: hash
            )
        }

        return SiteSnapshot(files: files, createdAt: Date())
    }

    private static func contentHash(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            guard !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

    private static func ensureRemoteDirectories(for relativePaths: [String], config: SyncConfig) async throws {
        let directories = Array(Set(relativePaths.flatMap { remoteDirectoryPaths(for: $0, config: config) }))
            .sorted { lhs, rhs in
                let lhsDepth = lhs.split(separator: "/").count
                let rhsDepth = rhs.split(separator: "/").count

                if lhsDepth == rhsDepth {
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                }

                return lhsDepth < rhsDepth
            }

        guard !directories.isEmpty else {
            return
        }

        try await Task.detached {
            let client = try FTPClient(config: config)
            defer { client.close() }

            for directory in directories {
                try Task.checkCancellation()
                try client.makeDirectory(path: directory)
            }
        }.value
    }

    private static func remoteRoot(_ root: String) -> String {
        let trimmed = root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : "/" + trimmed
    }

    private static func ftpCommandPath(config: SyncConfig, relativePath: String) -> String {
        var path = remoteRoot(config.root)
        if !relativePath.isEmpty {
            path += "/" + relativePath
        }

        return path.isEmpty ? "/" : path
    }

    private static func partition(_ changes: [FileChange], workerCount: Int) -> [[FileChange]] {
        guard workerCount > 1, changes.count > 1 else {
            return [changes]
        }

        var partitions = Array(repeating: [FileChange](), count: min(workerCount, changes.count))

        for (index, change) in changes.enumerated() {
            partitions[index % partitions.count].append(change)
        }

        return partitions
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

}

private final class FTPClient: @unchecked Sendable {
    private static let responseTimeout: TimeInterval = 12
    private let config: SyncConfig
    private let host: String
    private let port: UInt32
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var responseBuffer = Data()

    init(config: SyncConfig) throws {
        self.config = config
        let parsed = Self.parseHost(config.host)
        host = parsed.host
        port = parsed.port

        try openControlConnection()
        _ = try readResponse(expected: [220])
        try login()
    }

    func close() {
        // Encerrar não deve atrasar a interface aguardando uma resposta do servidor.
        try? writeCommand("QUIT")
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
    }

    func verifyRoot() throws -> String {
        let root = sanitizePath(config.root)
        guard !root.isEmpty, root != "/" else {
            return "Diretório raiz disponível."
        }

        _ = try sendCommand("CWD \(root)", expected: [250])
        return "Diretório raiz disponível."
    }

    func makeDirectory(path: String) throws {
        do {
            _ = try sendCommand("MKD \(sanitizePath(path))", expected: [257, 250])
        } catch FTPClientError.unexpectedResponse(let response) where response.code == 550 || response.message.localizedCaseInsensitiveContains("exists") {
            return
        }
    }

    func upload(fileURL: URL, remotePath: String) throws {
        let dataConnection = try openPassiveDataConnection()

        do {
            try writeCommand("STOR \(sanitizePath(remotePath))")
            _ = try readResponse(expected: [125, 150])
            try dataConnection.writeFile(fileURL)
            dataConnection.close()
            _ = try readResponse(expected: [226, 250])
        } catch {
            dataConnection.close()
            throw error
        }
    }

    func download(remotePath: String, to localURL: URL, progress: @escaping (Int64) -> Void) throws {
        let dataConnection = try openPassiveDataConnection()
        do {
            try writeCommand("RETR \(sanitizePath(remotePath))")
            _ = try readResponse(expected: [125, 150])
            try dataConnection.readFile(to: localURL, progress: progress)
            dataConnection.close()
            _ = try readResponse(expected: [226, 250])
        } catch {
            dataConnection.close()
            throw error
        }
    }

    func recursiveFiles(at root: String) throws -> [RemoteFile] {
        var files: [RemoteFile] = []
        try collectFiles(at: root.isEmpty ? "/" : root, relativePath: "", into: &files)
        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    func delete(remotePath: String) throws {
        do {
            _ = try sendCommand("DELE \(sanitizePath(remotePath))", expected: [250])
        } catch FTPClientError.unexpectedResponse(let response) where response.code == 550 || isRemoteMissingMessage(response.message) {
            return
        }
    }

    private func openControlConnection() throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(nil, host as CFString, port, &readStream, &writeStream)

        guard let read = readStream?.takeRetainedValue(), let write = writeStream?.takeRetainedValue() else {
            throw FTPClientError.connectionFailed("Não foi possível criar a conexão FTP.")
        }

        CFReadStreamSetProperty(read, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)
        CFWriteStreamSetProperty(write, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)

        inputStream = read
        outputStream = write

        inputStream?.open()
        outputStream?.open()
    }

    private func collectFiles(at remotePath: String, relativePath: String, into files: inout [RemoteFile]) throws {
        for entry in try listEntries(at: remotePath) {
            try Task.checkCancellation()
            let childRelativePath = relativePath.isEmpty ? entry.name : "\(relativePath)/\(entry.name)"
            let childRemotePath = remotePath == "/" ? "/\(entry.name)" : "\(remotePath)/\(entry.name)"
            if entry.isDirectory {
                try collectFiles(at: childRemotePath, relativePath: childRelativePath, into: &files)
            } else {
                files.append(RemoteFile(remotePath: childRemotePath, relativePath: childRelativePath, size: entry.size))
            }
        }
    }

    private func listEntries(at remotePath: String) throws -> [FTPDirectoryEntry] {
        let dataConnection = try openPassiveDataConnection()
        do {
            try writeCommand("MLSD \(sanitizePath(remotePath))")
            _ = try readResponse(expected: [125, 150])
            let data = try dataConnection.readAll()
            dataConnection.close()
            _ = try readResponse(expected: [226, 250])
            return parseMLSD(data)
        } catch {
            dataConnection.close()
            return try listLegacyEntries(at: remotePath)
        }
    }

    private func listLegacyEntries(at remotePath: String) throws -> [FTPDirectoryEntry] {
        let dataConnection = try openPassiveDataConnection()
        do {
            try writeCommand("NLST \(sanitizePath(remotePath))")
            _ = try readResponse(expected: [125, 150])
            let data = try dataConnection.readAll()
            dataConnection.close()
            _ = try readResponse(expected: [226, 250])

            let listing = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return try listing.components(separatedBy: .newlines).compactMap { rawName in
                let path = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = URL(fileURLWithPath: path).lastPathComponent
                guard isSafeEntryName(name) else { return nil }
                let childPath = remotePath == "/" ? "/\(name)" : "\(remotePath)/\(name)"
                let isDirectory = (try? sendCommand("CWD \(sanitizePath(childPath))", expected: [250])) != nil
                return FTPDirectoryEntry(name: name, isDirectory: isDirectory, size: nil)
            }
        } catch {
            dataConnection.close()
            throw error
        }
    }

    private func parseMLSD(_ data: Data) -> [FTPDirectoryEntry] {
        let listing = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return listing.components(separatedBy: .newlines).compactMap { line in
            guard let separator = line.firstIndex(of: " ") else { return nil }
            let facts = line[..<separator].lowercased()
            let name = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeEntryName(name), !facts.contains("type=cdir"), !facts.contains("type=pdir") else { return nil }
            let size = facts.split(separator: ";").first { $0.hasPrefix("size=") }.flatMap { Int64($0.dropFirst(5)) }
            if facts.contains("type=dir") { return FTPDirectoryEntry(name: name, isDirectory: true, size: nil) }
            if facts.contains("type=file") { return FTPDirectoryEntry(name: name, isDirectory: false, size: size) }
            return nil
        }
    }

    private func isSafeEntryName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }

    private func login() throws {
        let userResponse = try sendCommand("USER \(config.user)", expected: [230, 331])
        if userResponse.code == 331 {
            _ = try sendCommand("PASS \(config.password)", expected: [230])
        }

        _ = try sendCommand("TYPE I", expected: [200])
    }

    private func openPassiveDataConnection() throws -> FTPDataConnection {
        do {
            let response = try sendCommand("EPSV", expected: [229])
            let passivePort = try parseEPSVPort(response.message)
            return try FTPDataConnection(host: host, port: passivePort)
        } catch {
            let response = try sendCommand("PASV", expected: [227])
            let endpoint = try parsePASVEndpoint(response.message)
            return try FTPDataConnection(host: endpoint.host, port: endpoint.port)
        }
    }

    @discardableResult
    private func sendCommand(_ command: String, expected: Set<Int>) throws -> FTPResponse {
        try writeCommand(command)
        return try readResponse(expected: expected)
    }

    private func writeCommand(_ command: String) throws {
        guard let data = "\(command)\r\n".data(using: .utf8) else {
            throw FTPClientError.connectionFailed("Comando FTP inválido.")
        }

        try write(data)
    }

    private func write(_ data: Data) throws {
        guard let outputStream else {
            throw FTPClientError.connectionFailed("Conexão FTP fechada.")
        }

        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            var sent = 0
            while sent < data.count {
                let result = outputStream.write(baseAddress.advanced(by: sent), maxLength: data.count - sent)
                if result < 0 {
                    throw outputStream.streamError ?? FTPClientError.connectionFailed("Falha ao escrever no FTP.")
                }
                if result == 0 {
                    throw FTPClientError.connectionFailed("A conexão FTP foi interrompida.")
                }
                sent += result
            }
        }
    }

    private func readResponse(expected: Set<Int>) throws -> FTPResponse {
        let response = try readResponse()
        guard expected.contains(response.code) else {
            throw FTPClientError.unexpectedResponse(response)
        }

        return response
    }

    private func readResponse() throws -> FTPResponse {
        let deadline = Date().addingTimeInterval(Self.responseTimeout)
        let firstLine = try readLine(until: deadline)
        guard firstLine.count >= 3, let code = Int(firstLine.prefix(3)) else {
            throw FTPClientError.invalidResponse(firstLine)
        }

        var lines = [firstLine]

        if firstLine.dropFirst(3).first == "-" {
            while true {
                let line = try readLine(until: deadline)
                lines.append(line)
                if line.hasPrefix("\(code) ") {
                    break
                }
            }
        }

        return FTPResponse(code: code, message: lines.joined(separator: "\n"))
    }

    private func readLine(until deadline: Date) throws -> String {
        while true {
            if let range = responseBuffer.firstRange(of: Data([13, 10])) {
                let lineData = responseBuffer.subdata(in: responseBuffer.startIndex..<range.lowerBound)
                responseBuffer.removeSubrange(responseBuffer.startIndex..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .isoLatin1) ?? ""
            }

            guard let inputStream else {
                throw FTPClientError.connectionFailed("Conexão FTP fechada.")
            }

            switch inputStream.streamStatus {
            case .error:
                throw inputStream.streamError ?? FTPClientError.connectionFailed("Falha ao ler resposta do FTP.")
            case .closed, .atEnd:
                throw FTPClientError.connectionFailed("O servidor FTP fechou a conexão.")
            default:
                break
            }

            guard Date() < deadline else {
                throw FTPClientError.timedOut
            }

            guard inputStream.hasBytesAvailable else {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            var bytes = [UInt8](repeating: 0, count: 4 * 1024)
            let readCount = inputStream.read(&bytes, maxLength: bytes.count)

            if readCount < 0 {
                throw inputStream.streamError ?? FTPClientError.connectionFailed("Falha ao ler resposta do FTP.")
            }

            if readCount == 0 {
                throw FTPClientError.connectionFailed("O servidor FTP fechou a conexão.")
            }

            responseBuffer.append(bytes, count: readCount)
        }
    }

    private func parseEPSVPort(_ message: String) throws -> UInt32 {
        guard
            let start = message.firstIndex(of: "("),
            let end = message[start...].firstIndex(of: ")")
        else {
            throw FTPClientError.invalidResponse(message)
        }

        let payload = String(message[message.index(after: start)..<end])
        let delimiter = payload.first ?? "|"
        let parts = payload.split(separator: delimiter, omittingEmptySubsequences: false)

        guard let last = parts.last, let port = UInt32(last) else {
            throw FTPClientError.invalidResponse(message)
        }

        return port
    }

    private func parsePASVEndpoint(_ message: String) throws -> (host: String, port: UInt32) {
        guard
            let start = message.firstIndex(of: "("),
            let end = message[start...].firstIndex(of: ")")
        else {
            throw FTPClientError.invalidResponse(message)
        }

        let values = message[message.index(after: start)..<end]
            .split(separator: ",")
            .compactMap { UInt32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard values.count == 6 else {
            throw FTPClientError.invalidResponse(message)
        }

        let passiveHost = values[0...3].map(String.init).joined(separator: ".")
        let passivePort = (values[4] * 256) + values[5]
        return (passiveHost, passivePort)
    }

    private func sanitizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }

    private func isRemoteMissingMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return [
            "no such file",
            "not found",
            "does not exist",
            "não existe",
            "nao existe",
            "inexistente",
            "file unavailable"
        ].contains { lowercased.contains($0) }
    }

    private static func parseHost(_ value: String) -> (host: String, port: UInt32) {
        var cleaned = value
            .replacingOccurrences(of: "ftp://", with: "")
            .replacingOccurrences(of: "FTP://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }

        let parts = cleaned.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let port = UInt32(parts[1]) {
            return (parts[0], port)
        }

        return (cleaned, 21)
    }
}

private struct RemoteFile {
    let remotePath: String
    let relativePath: String
    let size: Int64?
}

private struct FTPDirectoryEntry {
    let name: String
    let isDirectory: Bool
    let size: Int64?
}

private final class FTPDataConnection {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    init(host: String, port: UInt32) throws {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(nil, host as CFString, port, &readStream, &writeStream)

        guard let read = readStream?.takeRetainedValue(), let write = writeStream?.takeRetainedValue() else {
            throw FTPClientError.connectionFailed("Não foi possível abrir a conexão de dados FTP.")
        }

        CFReadStreamSetProperty(read, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)
        CFWriteStreamSetProperty(write, CFStreamPropertyKey(kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanTrue)

        inputStream = read
        outputStream = write
        inputStream?.open()
        outputStream?.open()
    }

    func close() {
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
    }

    func readAll() throws -> Data {
        guard let inputStream else {
            throw FTPClientError.connectionFailed("Conexão de dados FTP fechada.")
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)

        while true {
            let count = inputStream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw inputStream.streamError ?? FTPClientError.connectionFailed("Falha ao ler dados do FTP.")
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return data
    }

    func readFile(to localURL: URL, progress: @escaping (Int64) -> Void) throws {
        guard let inputStream else {
            throw FTPClientError.connectionFailed("Conexão de dados FTP fechada.")
        }
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = localURL.deletingLastPathComponent().appendingPathComponent(".syncsite-download-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? handle.close() }

        do {
            var downloaded: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                let count = inputStream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw inputStream.streamError ?? FTPClientError.connectionFailed("Falha ao baixar arquivo do FTP.") }
                if count == 0 { break }
                try handle.write(contentsOf: Data(buffer[0..<count]))
                downloaded += Int64(count)
                progress(downloaded)
            }
            try? handle.close()
            if FileManager.default.fileExists(atPath: localURL.path) { try FileManager.default.removeItem(at: localURL) }
            try FileManager.default.moveItem(at: temporaryURL, to: localURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func writeFile(_ fileURL: URL) throws {
        guard let outputStream else {
            throw FTPClientError.connectionFailed("Conexão de dados FTP fechada.")
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }

            try chunk.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }

                var sent = 0
                while sent < chunk.count {
                    let result = outputStream.write(baseAddress.advanced(by: sent), maxLength: chunk.count - sent)
                    if result < 0 {
                        throw outputStream.streamError ?? FTPClientError.connectionFailed("Falha ao enviar dados ao FTP.")
                    }
                    if result == 0 {
                        throw FTPClientError.connectionFailed("A conexão de dados FTP foi interrompida.")
                    }
                    sent += result
                }
            }
        }
    }
}

private struct FTPResponse {
    let code: Int
    let message: String
}

private enum FTPClientError: LocalizedError {
    case connectionFailed(String)
    case timedOut
    case invalidResponse(String)
    case unexpectedResponse(FTPResponse)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        case .timedOut:
            return "O servidor FTP não respondeu em até 12 segundos. Confira o endereço, a porta, o firewall e a disponibilidade do servidor."
        case .invalidResponse(let response):
            return "Resposta FTP inválida:\n\(response)"
        case .unexpectedResponse(let response):
            return response.message
        }
    }
}

enum SyncError: LocalizedError {
    case fileFailed(change: FileChange, action: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .fileFailed(let change, let action, let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Falha ao \(action) o arquivo:\n\(change.path)\n\nDetalhes:\n\(trimmed.isEmpty ? "O servidor não retornou detalhes do erro." : trimmed)"
        }
    }

    var failedChange: FileChange? {
        switch self {
        case .fileFailed(let change, _, _):
            return change
        }
    }
}
