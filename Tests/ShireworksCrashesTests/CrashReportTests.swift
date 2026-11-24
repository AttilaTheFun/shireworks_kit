// A crash as the crash reporter hands it over, read into a CrashReport on
// every platform; and its signature: the same crash's the same, whatever
// changes from run to run, the app's own frames deciding where it has any.

import Foundation
import Testing
@testable import ShireworksCrashes

struct CrashReportTests {
    @Test func readFromTheEvent() throws {
        let report = try #require(CrashEvent.report(from: Fixtures.event()))
        #expect(report.id == "7d1b8e2c4f6a4b0e9c3d5a7f1e2b4c6d")
        #expect(report.date == Date(timeIntervalSince1970: 1_793_526_060.25))
        #expect(report.appVersion == "1.2.0")
        #expect(report.appBuild == "42")
        #expect(report.system == "macOS 27.2 (27C5000)")
        #expect(report.deviceModel == "Mac16,10")
        #expect(report.exceptionType == "EXC_BREAKPOINT")
        #expect(report.reason.hasSuffix("Fatal error: Index out of range in /Users/someone/Example/Sources/List.swift"))
        #expect(report.mechanism == "mach")

        // Innermost first; images by name alone, never their paths.
        #expect(report.frames.map(\.imageName) == ["libswiftCore.dylib", "Example", "Example", "dyld"])
        #expect(report.frames.map(\.inApp) == [false, true, true, false])
        let own = report.frames[1]
        #expect(own.symbol == nil)
        #expect(own.instructionAddress == 0x1_0000_1a2b)
        #expect(own.imageAddress == 0x1_0000_0000)
        #expect(own.offset == 0x1a2b)
        #expect(own.imageUUID == "8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9")
        #expect(own.location == "Example + 0x1a2b")
        #expect(report.frames[2].location == "main")

        // A thread with no frame read (its one at 0) is left out.
        #expect(report.threads == [CrashReport.Thread(id: 1, frames: [
            .init(imageName: "libsystem_kernel.dylib", imageUUID: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff",
                  instructionAddress: 0x1_8a00_1000, imageAddress: 0x1_8a00_0000, symbol: "__workq_kernreturn"),
            .init(imageName: "libsystem_pthread.dylib", instructionAddress: 0x1_8b00_1234, imageAddress: 0x1_8b00_0000,
                  symbol: "start_wqthread"),
        ])])
        #expect(report.images.map(\.name) == ["Example", "libswiftCore.dylib", "dyld", "libsystem_kernel.dylib"])
        #expect(report.images.first == CrashReport.Image(name: "Example", uuid: "8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
                                                         address: 0x1_0000_0000, size: 65536))
        #expect(report.breadcrumbs == ["09:40:58 [started] Breadcrumb Tracking", "09:40:59 [app.lifecycle] (state: foreground)"])
    }

    /// Only a crash is a report: anything else the reporter would send isn't.
    @Test func onlyACrash() throws {
        var event = try Fixtures.event()
        event["level"] = "error"
        #expect(CrashEvent.report(from: event) == nil)
        event["level"] = "fatal"
        event["exception"] = nil
        #expect(CrashEvent.report(from: event) == nil)
    }

    /// Without the app's context, its version and build from the release;
    /// the crashing thread from the thread marked crashed, or else the
    /// exception's.
    @Test func whatTheEventLeavesOut() throws {
        var event = try Fixtures.event()
        event["contexts"] = nil
        event["dist"] = nil
        var threads = try #require(event["threads"] as? [String: Any])
        var values = try #require(threads["values"] as? [[String: Any]])
        values[0]["crashed"] = nil
        threads["values"] = values
        event["threads"] = threads
        let report = try #require(CrashEvent.report(from: event))
        #expect(report.appVersion == "1.2.0")
        #expect(report.appBuild == "42")
        #expect(report.system == "unknown")
        #expect(report.deviceModel == "unknown")
        #expect(report.frames.count == 4)
        #expect(report.threads?.count == 1)
    }

    @Test func keptAsJSON() throws {
        let report = Fixtures.report()
        let data = try CrashStore.encoder.encode(report)
        #expect(try CrashStore.decoder.decode(CrashReport.self, from: data) == report)
    }

    @Test func fnv1a64() {
        #expect(CrashSignature.fnv1a64("") == "cbf29ce484222325")
        #expect(CrashSignature.fnv1a64("a") == "af63dc4c8601ec8c")
        #expect(CrashSignature.fnv1a64("foobar") == "85944171f73967e8")
    }

    /// The same crash, wherever and whenever: not its id, time, reason
    /// (addresses), version, device, other threads or the system's frames.
    @Test func theSameCrashSignsTheSame() {
        let first = Fixtures.report()
        var again = Fixtures.report(id: "crash-2", version: "1.3.0", build: "50", date: Date())
        again.reason = "KERN_INVALID_ADDRESS at 0x0000000000000028"
        again.deviceModel = "iPhone16,2"
        again.threads = nil
        again.frames[0].instructionAddress += 0x40
        again.frames[0].symbol = "swift_release"
        #expect(again.signature == first.signature)
        #expect(first.signature.count == 16)
        #expect(first.signature == Fixtures.report().signature)
    }

    @Test func anotherCrashSignsOtherwise() {
        let first = Fixtures.report()
        #expect(Fixtures.report(type: "EXC_BREAKPOINT").signature != first.signature)
        #expect(Fixtures.report(inApp: "Example.List.remove(at:)").signature != first.signature)
    }

    /// The app's own frames name it; with none, the top frames do.
    @Test func theAppsOwnFramesFirst() {
        let report = Fixtures.report()
        #expect(report.topFrames.map(\.location) == ["Example.List.item(at:)", "main"])
        var system = report
        for index in system.frames.indices { system.frames[index].inApp = false }
        #expect(system.topFrames.map(\.location) == ["swift_retain", "Example.List.item(at:)", "main"])
        #expect(system.signature != report.signature)
        // Then a system frame decides too.
        var other = system
        other.frames[0].symbol = "swift_release"
        #expect(other.signature != system.signature)
    }

    /// A release build's own frames have no symbol on the device, and their
    /// offsets move with every build: then the signature stays the same from
    /// build to build, by the reason (its numbers out) and the frames' images.
    @Test func withoutSymbolsTheSameCrashSignsTheSameAcrossBuilds() {
        func stripped(_ offset: UInt64, line: Int, address: String) -> CrashReport {
            var report = Fixtures.report(type: "EXC_BREAKPOINT")
            report.reason = "Example/List.swift:\(line): Fatal error: Index out of range (at \(address))"
            for index in report.frames.indices where report.frames[index].inApp {
                report.frames[index].symbol = nil
                report.frames[index].instructionAddress = 0x1_0000_0000 + offset + UInt64(index)
            }
            return report
        }
        let build1 = stripped(0x258c, line: 12, address: "0x10"), build2 = stripped(0x2610, line: 14, address: "0x28")
        #expect(build1.signature == build2.signature)
        // Another fatal error, in the same image: another crash.
        var other = build1
        other.reason = "Example/List.swift:12: Fatal error: Unexpectedly found nil"
        #expect(other.signature != build1.signature)
        #expect(CrashSignature.steady("KERN_INVALID_ADDRESS at 0x0000000000000028") == "KERN_INVALID_ADDRESS at #")
    }
}

