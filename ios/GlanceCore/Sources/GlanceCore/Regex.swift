import Foundation

/// Tiny NSRegularExpression wrapper (works identically on Linux Foundation and Apple platforms).
struct Rx {
    let re: NSRegularExpression
    init(_ pattern: String) { re = try! NSRegularExpression(pattern: pattern) }
    func matches(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
    func firstGroup(_ s: String, _ group: Int = 1) -> String? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
    func replacing(_ s: String, with t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }
}
