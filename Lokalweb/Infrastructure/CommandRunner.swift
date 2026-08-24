import Foundation

struct CommandResult {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

enum CommandError: LocalizedError {
    case launchFailed(String)
    case failed(executable: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .failed(let executable, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(URL(fileURLWithPath: executable).lastPathComponent) exited with status \(status)\(detail.isEmpty ? "." : ": \(detail)")"
        }
    }
}

struct CommandRunner {
    @discardableResult
    func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        allowFailure: Bool = false
    ) throws -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed("Could not launch \(executable): \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        let result = CommandResult(status: process.terminationStatus, output: output)
        if !allowFailure && !result.succeeded {
            throw CommandError.failed(executable: executable, status: result.status, output: result.output)
        }
        return result
    }

    func launch(
        _ executable: String,
        arguments: [String],
        outputURL: URL
    ) throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { _ in
            try? handle.close()
        }

        do {
            try process.run()
        } catch {
            try? handle.close()
            throw CommandError.launchFailed("Could not launch \(executable): \(error.localizedDescription)")
        }
    }

    @discardableResult
    func run(
        _ executable: String,
        arguments: [String],
        readingInputFrom inputURL: URL,
        allowFailure: Bool = false
    ) throws -> CommandResult {
        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? inputHandle.close() }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = inputHandle
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed("Could not launch \(executable): \(error.localizedDescription)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try checkedResult(executable: executable, status: process.terminationStatus, data: data, allowFailure: allowFailure)
    }

    func run(
        _ executable: String,
        arguments: [String],
        writingOutputTo outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw CommandError.launchFailed("Could not create the database export file.")
        }
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let outputHandle = try FileHandle(forWritingTo: temporaryURL)
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            throw CommandError.launchFailed("Could not launch \(executable): \(error.localizedDescription)")
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try outputHandle.close()
        _ = try checkedResult(
            executable: executable,
            status: process.terminationStatus,
            data: errorData,
            allowFailure: false
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        }
    }

    @discardableResult
    func runPipeline(
        firstExecutable: String,
        firstArguments: [String],
        secondExecutable: String,
        secondArguments: [String]
    ) throws -> CommandResult {
        let transferPipe = Pipe()
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lokalweb-command-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
            throw CommandError.launchFailed("Could not create a temporary command log.")
        }
        defer { try? FileManager.default.removeItem(at: logURL) }
        let logHandle = try FileHandle(forWritingTo: logURL)

        let first = Process()
        first.executableURL = URL(fileURLWithPath: firstExecutable)
        first.arguments = firstArguments
        first.standardOutput = transferPipe
        first.standardError = logHandle

        let second = Process()
        second.executableURL = URL(fileURLWithPath: secondExecutable)
        second.arguments = secondArguments
        second.standardInput = transferPipe
        second.standardOutput = logHandle
        second.standardError = logHandle

        do {
            try second.run()
            try first.run()
        } catch {
            if first.isRunning { first.terminate() }
            if second.isRunning { second.terminate() }
            try? logHandle.close()
            throw CommandError.launchFailed("Could not launch database import pipeline: \(error.localizedDescription)")
        }

        first.waitUntilExit()
        transferPipe.fileHandleForWriting.closeFile()
        second.waitUntilExit()
        try logHandle.close()
        let data = (try? Data(contentsOf: logURL)) ?? Data()

        if first.terminationStatus != 0 {
            return try checkedResult(executable: firstExecutable, status: first.terminationStatus, data: data, allowFailure: false)
        }
        return try checkedResult(executable: secondExecutable, status: second.terminationStatus, data: data, allowFailure: false)
    }

    private func checkedResult(
        executable: String,
        status: Int32,
        data: Data,
        allowFailure: Bool
    ) throws -> CommandResult {
        let result = CommandResult(status: status, output: String(data: data, encoding: .utf8) ?? "")
        if !allowFailure && !result.succeeded {
            throw CommandError.failed(executable: executable, status: result.status, output: result.output)
        }
        return result
    }
}
