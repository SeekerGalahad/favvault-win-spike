# PlatformProbe

A sanitized, self-contained Swift package that exercises the Foundation /
Dispatch / runtime API surface needed by a file-backed note application on
Windows. It contains no application code, no proprietary identifiers and no
data copied from any private repository.

## Layout

```
Sources/ProbeCore/         path, file, text, date, threading, process probes
Tests/ProbeCoreTests/      XCTest assertions + a machine-readable summary line
imports/                   one-line `import <module>` files, type-checked one by one
scripts/probe-imports.ps1  prints the module import matrix (informational)
.github/workflows/         Windows CI: install Swift, build, test, import matrix
```

## What it measures

- `URL.path` separators, prefix checks, `standardizedFileURL`, `lastPathComponent`
- case-insensitive lookup with case-preserving names
- NFC/NFD file names, normalisation, folding
- atomic write (`Data.write(options: .atomic)`) and replace-while-open behaviour
- move / copy / overwrite semantics, cross-volume move, `\\?\` long paths
- CRLF byte preservation, `FileHandle` offsets
- `NSRegularExpression` with CJK text and UTF-16 ranges, `\p{Script=Han}`
- `DateFormatter` / `ISO8601DateFormatter` / `Calendar`
- `JSONEncoder` / `JSONDecoder`, `CharacterSet`, `String` comparison
- `DispatchQueue`, `NSLock`, task groups, `Process`, `NotificationCenter`

Each probe prints `PROBE|<name>|<value>` lines. Tests assert only platform
invariants; platform-specific values are reported and not asserted, so the
log doubles as the evidence record.

## Run locally

```
swift build
swift test
pwsh ./scripts/probe-imports.ps1
```

## CI

`.github/workflows/windows-s1.yml` pins the Swift toolchain (see the comment
block in that file for version, source and lookup date) and runs
`swift build` and `swift test` as hard gates on `windows-latest`.
