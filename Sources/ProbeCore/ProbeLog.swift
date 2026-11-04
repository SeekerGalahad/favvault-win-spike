import Foundation

/// Very small reporting helper: every observation is printed as a single
/// machine-greppable line, `PROBE|name|value`.
public enum ProbeLog {
    public static func record(_ name: String, _ value: Any) {
        let text = String(describing: value)
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        print("PROBE|\(name)|\(text)")
    }

    public static func recordError(_ name: String, _ error: Error) {
        let ns = error as NSError
        print("PROBE|\(name)|ERROR|\(ns.domain)|\(ns.code)|\(ns.localizedDescription)")
    }
}

/// One probe outcome. `ok` only encodes invariants that must hold on a
/// functioning platform; platform-specific values are carried in `details`
/// and are reported rather than asserted.
public struct ProbeResult {
    public let name: String
    public let ok: Bool
    public let details: [String: String]

    public init(name: String, ok: Bool, details: [String: String] = [:]) {
        self.name = name
        self.ok = ok
        self.details = details
        ProbeLog.record(name, ok ? "PASS" : "FAIL")
        for key in details.keys.sorted() {
            ProbeLog.record("\(name).\(key)", details[key] ?? "")
        }
    }
}
