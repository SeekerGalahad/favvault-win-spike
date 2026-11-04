import Dispatch
import Foundation

/// Runtime probes: threading, file handles, child processes, notifications.
public enum SystemProbe {

    // MARK: - Dispatch

    public static func concurrentQueue() -> ProbeResult {
        let lock = NSLock()
        var counter = 0
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            lock.lock()
            counter += 1
            lock.unlock()
        }
        let serial = DispatchQueue(label: "probe.serial")
        var ordered: [Int] = []
        for value in 0..<64 {
            serial.sync { ordered.append(value) }
        }
        let details: [String: String] = [
            "concurrentCount": "\(counter)",
            "serialCount": "\(ordered.count)",
            "serialOrdered": "\(ordered == Array(0..<64))"
        ]
        return ProbeResult(name: "system.dispatch", ok: counter == 128 && ordered.count == 64, details: details)
    }

    public static func asyncTaskGroup() async -> ProbeResult {
        var total = 0
        await withTaskGroup(of: Int.self) { group in
            for value in 1...50 {
                group.addTask { value }
            }
            for await value in group {
                total += value
            }
        }
        let details: [String: String] = ["sum": "\(total)", "expected": "1275"]
        return ProbeResult(name: "system.asyncTasks", ok: total == 1275, details: details)
    }

    // MARK: - FileHandle

    public static func fileHandle() -> ProbeResult {
        do {
            let dir = try PathProbe.makeSandbox("handle")
            defer { PathProbe.dispose(dir) }

            let url = dir.appendingPathComponent("stream.bin")
            try Data("abcdefgh".utf8).write(to: url)

            let reader = try FileHandle(forReadingFrom: url)
            defer { reader.closeFile() }

            let firstChunk = reader.readData(ofLength: 3)
            let offsetAfterFirst = reader.offsetInFile
            reader.seek(toFileOffset: 5)
            let tail = reader.readData(ofLength: 3)
            let finalOffset = reader.offsetInFile

            let details: [String: String] = [
                "firstChunk": String(data: firstChunk, encoding: .utf8) ?? "",
                "offsetAfterFirst": "\(offsetAfterFirst)",
                "tail": String(data: tail, encoding: .utf8) ?? "",
                "finalOffset": "\(finalOffset)"
            ]
            let ok = String(data: firstChunk, encoding: .utf8) == "abc"
                && offsetAfterFirst == 3
                && String(data: tail, encoding: .utf8) == "fgh"
                && finalOffset == 8
            return ProbeResult(name: "system.fileHandle", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("system.fileHandle", error)
            return ProbeResult(name: "system.fileHandle", ok: false)
        }
    }

    // MARK: - Child process

    public static func childProcess() -> ProbeResult {
        let environment = ProcessInfo.processInfo.environment
        let shell = environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["/c", "echo", "probe-output"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var details: [String: String] = ["shell": shell]
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            details["exitCode"] = "\(process.terminationStatus)"
            details["output"] = output
            let ok = process.terminationStatus == 0 && output.contains("probe-output")
            return ProbeResult(name: "system.childProcess", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("system.childProcess", error)
            details["result"] = "spawn-failed"
            return ProbeResult(name: "system.childProcess", ok: false, details: details)
        }
    }

    // MARK: - Notifications

    public static func notifications() -> ProbeResult {
        final class Box {
            var fired = false
        }
        let box = Box()
        let name = Notification.Name("probe.notification")
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            box.fired = true
        }
        NotificationCenter.default.post(name: name, object: nil)
        NotificationCenter.default.removeObserver(token)

        let details: [String: String] = ["fired": "\(box.fired)"]
        return ProbeResult(name: "system.notifications", ok: box.fired, details: details)
    }

    // MARK: - Bundle of everything

    public static func runAllSynchronously() -> [ProbeResult] {
        return [
            PathProbe.pathSemantics(),
            PathProbe.caseBehavior(),
            PathProbe.unicodeNames(),
            PathProbe.lineEndings(),
            PathProbe.atomicWrite(),
            PathProbe.atomicWriteWhileOpen(),
            PathProbe.moveAndCopysemantics(),
            PathProbe.crossVolumeMove(),
            PathProbe.longPathBehavior(),
            TextProbe.regexChinese(),
            TextProbe.regexUnicodeProperty(),
            TextProbe.normalisation(),
            TextProbe.characterSets(),
            TextProbe.dateFormatting(),
            TextProbe.jsonRoundTrip(),
            TextProbe.stringSearch(),
            concurrentQueue(),
            fileHandle(),
            childProcess(),
            notifications()
        ]
    }
}
