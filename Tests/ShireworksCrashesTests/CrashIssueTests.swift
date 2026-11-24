// What a crash's issue says: its title, its body with the crashing thread
// and the folded parts, the markers that find it again, redacted, and kept
// under GitHub's limit however big the crash.

import Foundation
import Testing
@testable import ShireworksCrashes

struct CrashIssueTests {
    @Test func theTitle() {
        #expect(CrashIssue.title(for: Fixtures.report())
            == "Crash: EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x0000000000000010 (Example.List.item(at:))")
        var long = Fixtures.report()
        long.reason = String(repeating: "x", count: 200) + "\nsecond line"
        long.frames[1].symbol = nil
        let title = CrashIssue.title(for: long)
        #expect(title.hasPrefix("Crash: EXC_BAD_ACCESS: xxx"))
        #expect(title.contains("…"))
        #expect(!title.contains("second line"))
        #expect(title.hasSuffix("(Example + 0x1a2b)"))
    }

    @Test func theBody() {
        let report = Fixtures.report()
        let body = CrashIssue.body(for: report)
        #expect(body.hasPrefix("**EXC_BAD_ACCESS**: KERN_INVALID_ADDRESS at 0x0000000000000010"))
        #expect(body.contains("Caught as: mach"))
        #expect(body.contains("0   libswiftCore.dylib              0x0000000190123456  swift_retain (libswiftCore.dylib + 0x123456)"))
        #expect(body.contains("1   Example                         0x0000000100001a2b  Example.List.item(at:) (Example + 0x1a2b)"))
        #expect(body.contains("| Version | 1.2.0 (42) |"))
        #expect(body.contains("| Device | iPhone17,1 |"))
        #expect(body.contains("| Crashed | 2026-11-01T09:41:00Z |"))
        #expect(body.contains("<details><summary>Other threads (1)</summary>"))
        #expect(body.contains("Thread 1 (worker):"))
        #expect(body.contains("<details><summary>Binary images (2)</summary>"))
        #expect(body.contains("0x0000000100000000  Example                         8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9  (65536 bytes)"))
        #expect(body.contains("<details><summary>Breadcrumbs (1)</summary>"))
        #expect(body.hasSuffix("<!-- shireworks-crash: \(report.signature) -->\n<!-- shireworks-crash-version: 1.2.0 -->\n"))
        // In that order.
        let order = ["**EXC_BAD_ACCESS**", "The crashing thread", "| Version |", "Other threads", "Binary images", "Breadcrumbs",
                     "<!-- shireworks-crash:"]
        let places = order.compactMap { body.range(of: $0)?.lowerBound }
        #expect(places.count == order.count && places == places.sorted())
    }

    /// Nothing that looks like a person's goes out: their home folder's
    /// name, an email address, a token, and the host's own patterns.
    @Test func redacted() {
        var report = Fixtures.report()
        report.reason = "Fatal error in /Users/someone/Example/List.swift for someone@example.com with ghp_abcdefghij0123456789 account 4242"
        report.breadcrumbs = ["opened /home/someone/notes.txt"]
        let body = CrashIssue.body(for: report, redactions: [#"account \d+"#])
        #expect(body.contains("/Users/<redacted>/Example/List.swift"))
        #expect(body.contains("/home/<redacted>/notes.txt"))
        #expect(!body.contains("someone"))
        #expect(!body.contains("ghp_abcdefghij"))
        #expect(!body.contains("4242"))
        #expect(!CrashIssue.title(for: report).contains("someone"))
    }

    /// However big the crash, the body stays under the limit: the folded
    /// parts cut first, the crashing thread whole while it fits.
    @Test func keptUnderTheLimit() {
        var report = Fixtures.report()
        let frame = CrashReport.Frame(imageName: "libsystem_kernel.dylib", instructionAddress: 0x1_8a00_1000, imageAddress: 0x1_8a00_0000,
                                      symbol: "__workq_kernreturn")
        report.threads = (1...200).map { CrashReport.Thread(id: $0, frames: Array(repeating: frame, count: 30)) }
        report.images = (0..<2000).map { CrashReport.Image(name: "Library\($0).dylib", uuid: UUID().uuidString, address: UInt64($0) << 20) }
        report.breadcrumbs = (0..<100).map { "breadcrumb \($0)" }
        let body = CrashIssue.body(for: report)
        #expect(body.utf8.count <= CrashIssue.limit)
        #expect(body.contains("Example.List.item(at:)"))
        #expect(body.contains("more left out"))
        #expect(body.hasSuffix("<!-- shireworks-crash-version: 1.2.0 -->\n"))

        // A small limit: the largest folded parts go, the crashing thread stays.
        let small = CrashIssue.body(for: report, limit: 1_200)
        #expect(small.utf8.count <= 1_200)
        #expect(!small.contains("Other threads") && !small.contains("Binary images"))
        #expect(small.contains("Example + 0x3f20"))
        #expect(small.contains("<!-- shireworks-crash: \(report.signature) -->"))

        // Smaller still: the crashing thread's outer frames, then the end of the summary.
        let tiny = CrashIssue.body(for: report, limit: 600)
        #expect(tiny.utf8.count <= 600)
        #expect(tiny.hasSuffix("<!-- shireworks-crash-version: 1.2.0 -->\n"))
    }

    @Test func theComment() {
        let comment = CrashIssue.comment(for: Fixtures.report(version: "1.3.0", build: "50"))
        #expect(comment.hasPrefix("Again in 1.3.0 (50), iPhone17,1, iOS 27.2, 2026-11-01T09:41:00Z\n\n```\n0   libswiftCore.dylib"))
        #expect(comment.hasSuffix("```\n"))
    }

    @Test func theVersionRecorded() {
        let body = CrashIssue.body(for: Fixtures.report())
        #expect(CrashIssue.recordedVersion(in: body) == "1.2.0")
        let later = CrashIssue.body(body, recording: "1.10.0")
        #expect(CrashIssue.recordedVersion(in: later) == "1.10.0")
        #expect(later.components(separatedBy: "shireworks-crash-version").count == 2)
        #expect(CrashIssue.recordedVersion(in: "no marker") == nil)
        #expect(CrashIssue.recordedVersion(in: CrashIssue.body("edited by hand", recording: "2.0")) == "2.0")
    }

    @Test func versionsComparedAsNumbers() {
        #expect(CrashIssue.isVersion("1.10.0", newerThan: "1.9.3"))
        #expect(CrashIssue.isVersion("0.10.2", newerThan: "0.9.34"))
        #expect(CrashIssue.isVersion("2", newerThan: "1.99"))
        #expect(!CrashIssue.isVersion("1.2", newerThan: "1.2.0"))
        #expect(!CrashIssue.isVersion("1.2.0", newerThan: "1.2.0"))
        #expect(!CrashIssue.isVersion("1.1.9", newerThan: "1.2"))
        #expect(CrashIssue.isVersion("1.3b1", newerThan: "1.2"))
    }
}
