import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ value: String) {
        lock.lock()
        text += value
        lock.unlock()
    }

    func value() -> String {
        lock.lock()
        let current = text
        lock.unlock()
        return current
    }
}

enum CommandRunner {
    static func runSyncsite(
        in projectURL: URL,
        arguments: [String],
        standardInput: String? = nil,
        output: @escaping @MainActor (String) -> Void
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let inputPipe = Pipe()
            let outputCollector = OutputCollector()

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.currentDirectoryURL = projectURL
            process.arguments = ["-lc", "./syncsite \(arguments.map(shellQuote).joined(separator: " "))"]
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            if standardInput != nil {
                process.standardInput = inputPipe
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return
                }

                outputCollector.append(text)

                Task { @MainActor in
                    output(text)
                }
            }

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                let finalOutput = outputCollector.value()
                continuation.resume(returning: CommandResult(status: process.terminationStatus, output: finalOutput))
            }

            do {
                try process.run()

                if let standardInput, let data = standardInput.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                Task { @MainActor in
                    output("Erro ao executar syncsite: \(error.localizedDescription)\n")
                }
                continuation.resume(returning: CommandResult(status: 1, output: error.localizedDescription))
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
