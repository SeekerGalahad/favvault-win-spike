import Foundation

/// File-system and path probes. All data is generated locally; nothing here
/// mirrors any application structure.
public enum PathProbe {

    // MARK: - Sandbox

    public static func makeSandbox(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func dispose(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - URL.path semantics

    public static func pathSemantics() -> ProbeResult {
        do {
            let dir = try makeSandbox("path")
            defer { dispose(dir) }

            let child = dir.appendingPathComponent("alpha").appendingPathComponent("beta.txt")
            try FileManager.default.createDirectory(
                at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("sample".utf8).write(to: child)

            let path = child.path
            let rootPath = dir.path
            let backslashes = path.filter { $0 == "\\" }.count
            let slashes = path.filter { $0 == "/" }.count
            let mixed = backslashes > 0 && slashes > 0
            let prefixWorks = path.hasPrefix(rootPath)
            let last = child.lastPathComponent
            let standardizedSame = child.standardizedFileURL.path == path
            let existsViaPath = FileManager.default.fileExists(atPath: path)
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let size = values?.fileSize ?? -1

            let details: [String: String] = [
                "path": path,
                "separatorBackslashCount": "\(backslashes)",
                "separatorSlashCount": "\(slashes)",
                "mixedSeparators": "\(mixed)",
                "prefixCheckAgainstRoot": "\(prefixWorks)",
                "lastPathComponent": last,
                "standardizedEqualsRaw": "\(standardizedSame)",
                "existsViaRawPath": "\(existsViaPath)",
                "sizeViaResourceValues": "\(size)"
            ]
            // Invariant: a path we build ourselves must be usable for a prefix
            // check and for file lookup; separators must not be mixed.
            let ok = prefixWorks && existsViaPath && !mixed && last == "beta.txt"
            return ProbeResult(name: "path.semantics", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("path.semantics", error)
            return ProbeResult(name: "path.semantics", ok: false)
        }
    }

    // MARK: - Case sensitivity and name preservation

    public static func caseBehavior() -> ProbeResult {
        do {
            let dir = try makeSandbox("case")
            defer { dispose(dir) }

            let original = dir.appendingPathComponent("Alpha.txt")
            try Data("one".utf8).write(to: original)

            let lower = dir.appendingPathComponent("alpha.txt")
            let visibleViaLower = FileManager.default.fileExists(atPath: lower.path)
            let readViaLower = (try? String(contentsOf: lower, encoding: .utf8)) ?? ""

            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let preserved = names.contains("Alpha.txt")

            // Second write through the other casing must hit the same file.
            try Data("two".utf8).write(to: lower)
            let originalContent = (try? String(contentsOf: original, encoding: .utf8)) ?? ""
            let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: dir.path).count) ?? -1

            let details: [String: String] = [
                "visibleViaOtherCase": "\(visibleViaLower)",
                "readViaOtherCase": readViaLower,
                "listedName": names.joined(separator: ","),
                "originalCasePreserved": "\(preserved)",
                "originalAfterWriteViaOtherCase": originalContent,
                "fileCountAfterSecondWrite": "\(fileCount)"
            ]
            let ok = visibleViaLower && preserved && fileCount == 1 && originalContent == "two"
            return ProbeResult(name: "path.caseBehavior", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("path.caseBehavior", error)
            return ProbeResult(name: "path.caseBehavior", ok: false)
        }
    }

    // MARK: - Unicode normalisation of names

    public static func unicodeNames() -> ProbeResult {
        do {
            let dir = try makeSandbox("unicode")
            defer { dispose(dir) }

            let precomposed = "caf\u{00E9}-sample.txt"          // NFC
            let decomposed = "cafe\u{0301}-sample.txt"          // NFD
            let written = dir.appendingPathComponent(precomposed)
            try Data("body".utf8).write(to: written)

            let nfdLookup = dir.appendingPathComponent(decomposed)
            let nfdResolves = FileManager.default.fileExists(atPath: nfdLookup.path)
            let listed = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let listedScalarCount = listed.first.map { $0.unicodeScalars.count } ?? -1

            // Round-trip of the *written* spelling must always work.
            let roundTrip = (try? String(contentsOf: written, encoding: .utf8)) ?? ""

            let details: [String: String] = [
                "writtenName": precomposed,
                "decomposedLookupResolves": "\(nfdResolves)",
                "listedName": listed.joined(separator: ","),
                "listedScalarCount": "\(listedScalarCount)",
                "roundTripContent": roundTrip
            ]
            // Only the round-trip is an invariant; cross-form lookup is recorded.
            let ok = roundTrip == "body" && listed.count == 1
            return ProbeResult(name: "path.unicodeNames", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("path.unicodeNames", error)
            return ProbeResult(name: "path.unicodeNames", ok: false)
        }
    }

    // MARK: - Line endings

    public static func lineEndings() -> ProbeResult {
        do {
            let dir = try makeSandbox("eol")
            defer { dispose(dir) }

            let text = "alpha\r\nbeta\r\ngamma"
            let url = dir.appendingPathComponent("note.txt")
            try Data(text.utf8).write(to: url)

            let raw = (try? Data(contentsOf: url)) ?? Data()
            let reread = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            // Count scalar-wise: in Swift a CRLF pair is a single Character,
            // so Character counting would hide the line ending entirely.
            let crCount = reread.unicodeScalars.filter { $0 == "\r" }.count
            let lfCount = reread.unicodeScalars.filter { $0 == "\n" }.count

            // Appending through FileHandle must not rewrite existing bytes.
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(Data("\r\ndelta".utf8))
            handle.closeFile()
            let after = (try? Data(contentsOf: url)) ?? Data()

            let details: [String: String] = [
                "byteCount": "\(raw.count)",
                "crScalarCount": "\(crCount)",
                "lfScalarCount": "\(lfCount)",
                "characterCount": "\(reread.count)",
                "bytesUnchangedByWrite": "\(raw == Data(text.utf8))",
                "appendByteCount": "\(after.count)"
            ]
            let ok = raw == Data(text.utf8) && crCount == 2 && lfCount == 2
            return ProbeResult(name: "path.lineEndings", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("path.lineEndings", error)
            return ProbeResult(name: "path.lineEndings", ok: false)
        }
    }

    // MARK: - Atomic write

    public static func atomicWrite() -> ProbeResult {
        do {
            let dir = try makeSandbox("atomic")
            defer { dispose(dir) }

            let url = dir.appendingPathComponent("note.txt")
            try Data("v1".utf8).write(to: url)
            try Data("v2".utf8).write(to: url, options: .atomic)
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

            // Leftover temporary files would indicate a broken replace.
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let strays = names.filter { $0 != "note.txt" }

            let details: [String: String] = [
                "contentAfterAtomicWrite": content,
                "directoryEntries": names.joined(separator: ","),
                "strayEntries": "\(strays.count)"
            ]
            let ok = content == "v2" && strays.isEmpty
            return ProbeResult(name: "file.atomicWrite", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("file.atomicWrite", error)
            return ProbeResult(name: "file.atomicWrite", ok: false)
        }
    }

    /// Replace semantics while another handle is open. Whether the write is
    /// rejected is recorded; the invariant is that the file never ends up
    /// unreadable or truncated.
    public static func atomicWriteWhileOpen() -> ProbeResult {
        do {
            let dir = try makeSandbox("locked")
            defer { dispose(dir) }

            let url = dir.appendingPathComponent("note.txt")
            try Data("original".utf8).write(to: url)

            let reader = try FileHandle(forReadingFrom: url)
            defer { reader.closeFile() }

            var threw = false
            var errorText = "none"
            var errorCode = "-"
            do {
                try Data("replacement".utf8).write(to: url, options: .atomic)
            } catch {
                threw = true
                let ns = error as NSError
                errorText = "\(ns.domain)/\(ns.localizedDescription)"
                errorCode = "\(ns.code)"
            }

            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "<unreadable>"
            let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attributes[.size] as? Int) ?? -1

            let details: [String: String] = [
                "threw": "\(threw)",
                "error": errorText,
                "errorCode": errorCode,
                "contentAfterAttempt": content,
                "sizeAfterAttempt": "\(size)"
            ]
            let ok = content == "original" || content == "replacement"
            return ProbeResult(name: "file.atomicWriteWhileOpen", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("file.atomicWriteWhileOpen", error)
            return ProbeResult(name: "file.atomicWriteWhileOpen", ok: false)
        }
    }

    // MARK: - Move / copy / rename

    public static func moveAndCopysemantics() -> ProbeResult {
        do {
            let dir = try makeSandbox("move")
            defer { dispose(dir) }

            let source = dir.appendingPathComponent("source.txt")
            try Data("payload".utf8).write(to: source)

            let renamed = dir.appendingPathComponent("renamed.txt")
            try FileManager.default.moveItem(at: source, to: renamed)

            let copy = dir.appendingPathComponent("copy.txt")
            try FileManager.default.copyItem(at: renamed, to: copy)

            let moved = FileManager.default.fileExists(atPath: source.path)
            let renamedBody = (try? String(contentsOf: renamed, encoding: .utf8)) ?? ""
            let copyBody = (try? String(contentsOf: copy, encoding: .utf8)) ?? ""

            // Overwriting move must succeed or fail predictably, never corrupt.
            let overwriteTarget = dir.appendingPathComponent("target.txt")
            try Data("old".utf8).write(to: overwriteTarget)
            var overwriteThrew = false
            do {
                try FileManager.default.moveItem(at: copy, to: overwriteTarget)
            } catch {
                overwriteThrew = true
            }
            let targetBody = (try? String(contentsOf: overwriteTarget, encoding: .utf8)) ?? "<unreadable>"

            let details: [String: String] = [
                "sourceStillExists": "\(moved)",
                "renamedBody": renamedBody,
                "copyBody": copyBody,
                "overwriteMoveThrew": "\(overwriteThrew)",
                "overwriteTargetBody": targetBody
            ]
            let ok = !moved && renamedBody == "payload" && copyBody == "payload"
                && (targetBody == "payload" || targetBody == "old")
            return ProbeResult(name: "file.moveAndCopy", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("file.moveAndCopy", error)
            return ProbeResult(name: "file.moveAndCopy", ok: false)
        }
    }

    // MARK: - Cross-volume move

    public static func crossVolumeMove() -> ProbeResult {
        let alternativeRoot = "D:\\"
        var details: [String: String] = ["candidateVolume": alternativeRoot]

        guard FileManager.default.fileExists(atPath: alternativeRoot) else {
            details["result"] = "skipped-no-second-volume"
            return ProbeResult(name: "file.crossVolumeMove", ok: true, details: details)
        }
        do {
            let dir = try makeSandbox("cross")
            defer { dispose(dir) }

            let foreign = URL(fileURLWithPath: alternativeRoot)
                .appendingPathComponent("probe-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: foreign) }

            let source = dir.appendingPathComponent("payload.bin")
            try Data(repeating: 7, count: 4096).write(to: source)

            let destination = foreign.appendingPathComponent("payload.bin")
            var threw = false
            var errorCode = "-"
            do {
                try FileManager.default.moveItem(at: source, to: destination)
            } catch {
                threw = true
                errorCode = "\((error as NSError).code)"
            }

            let arrived = FileManager.default.fileExists(atPath: destination.path)
            let size = (try? Data(contentsOf: destination).count) ?? -1
            let sourceGone = !FileManager.default.fileExists(atPath: source.path)

            details["threw"] = "\(threw)"
            details["errorCode"] = errorCode
            details["arrived"] = "\(arrived)"
            details["size"] = "\(size)"
            details["sourceGone"] = "\(sourceGone)"

            let ok = !threw && arrived && size == 4096 && sourceGone
            return ProbeResult(name: "file.crossVolumeMove", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("file.crossVolumeMove", error)
            return ProbeResult(name: "file.crossVolumeMove", ok: false)
        }
    }

    // MARK: - Long paths

    public static func longPathBehavior() -> ProbeResult {
        do {
            let dir = try makeSandbox("long")
            defer { dispose(dir) }

            var deep = dir
            var depth = 0
            while deep.path.count < 300 {
                deep = deep.appendingPathComponent("segment-0123456789abcdef")
                depth += 1
            }
            var plainError = "none"
            var nestedOK = false
            do {
                try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
                nestedOK = FileManager.default.fileExists(atPath: deep.path)
            } catch {
                let ns = error as NSError
                plainError = "\(ns.domain)/\(ns.code)"
            }

            let prefixedPath = "\\\\?\\" + deep.path
            let payloadPath = prefixedPath + "\\leaf.txt"
            var prefixedError = "none"
            var prefixedOK = false
            do {
                try Data("leaf".utf8).write(to: URL(fileURLWithPath: payloadPath))
                prefixedOK = FileManager.default.fileExists(atPath: payloadPath)
            } catch {
                let ns = error as NSError
                prefixedError = "\(ns.domain)/\(ns.code)"
            }

            let details: [String: String] = [
                "targetLength": "\(payloadPath.count)",
                "depth": "\(depth)",
                "plainCreateOK": "\(nestedOK)",
                "plainError": plainError,
                "prefixedWriteOK": "\(prefixedOK)",
                "prefixedError": prefixedError
            ]
            // No hard invariant: the point is to record the boundary.
            return ProbeResult(name: "path.longPath", ok: true, details: details)
        } catch {
            ProbeLog.recordError("path.longPath", error)
            return ProbeResult(name: "path.longPath", ok: false)
        }
    }
}
