// A crash as the crash recorder hands it over, read into a CrashReport on
// every platform; and its signature: the same crash's the same, whatever
// changes from run to run, the app's own frames deciding where it has any.

import Foundation
import Testing
@testable import ShireworksCrashes

struct CrashReportTests {
    @Test func readFromTheRecord() throws {
        let report = try #require(CrashRecording.report(from: Fixtures.record()))
        #expect(report.id == "84F501DB-DE74-4B02-817D-343BAB6B2E6E")
        #expect(abs(report.date.timeIntervalSince1970 - 1_795_544_825.779506) < 0.000_01)
        #expect(report.appVersion == "1.2.0")
        #expect(report.appBuild == "42")
        #expect(report.system == "macOS 27.0.1 (26A434)")
        #expect(report.deviceModel == "VirtualMac2,1")
        #expect(report.exceptionType == "EXC_BREAKPOINT")
        // The Swift runtime's message, beside libswiftCore's image.
        #expect(report.reason == "Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range\n")
        #expect(report.mechanism == "mach")
        #expect(report.breadcrumbs == nil)

        // Innermost first, as the recorder writes them; the app's own: its
        // executable's (the report's CFBundleExecutable).
        #expect(report.frames.map(\.imageName) == ["libswiftCore.dylib", "libswiftCore.dylib", "libswiftCore.dylib",
                                                   "libswiftCore.dylib", "Example", "dyld"])
        #expect(report.frames.map(\.inApp) == [false, false, false, false, true, false])
        let own = report.frames[4]
        #expect(own == CrashReport.Frame(imageName: "Example", imageUUID: "1C2B3187-191D-3AA4-A387-77B4336C4EF9",
                                         instructionAddress: 4_369_489_296, imageAddress: 4_369_481_728, symbol: "main", inApp: true))
        #expect(own.offset == 0x1d90)
        #expect(own.location == "main")
        #expect(report.frames[3].symbolName == "$sSayxSicig")

        // A thread with no frame (the recorder's) is left out.
        let other = try #require(report.threads?.first)
        #expect(report.threads?.count == 1)
        #expect(other.id == 1)
        #expect(other.frames.map(\.location) == ["__semwait_signal", "nanosleep", "sleep", "monitorThreadCache", "_pthread_start",
                                                 "thread_start"])
        #expect(other.frames[3].inApp)
        // Images by their file name alone, never their path.
        #expect(report.images.map(\.name) == ["Example", "libsystem_c.dylib", "libsystem_kernel.dylib", "libsystem_pthread.dylib",
                                              "libswiftCore.dylib", "dyld"])
        #expect(report.images.first == CrashReport.Image(name: "Example", uuid: "1C2B3187-191D-3AA4-A387-77B4336C4EF9",
                                                         address: 4_369_481_728, size: 409_600))
        #expect(report.topFrames.map(\.location) == ["main"])
    }

    /// Only a crash is a report: not a clean exit, nor one marked not fatal,
    /// nor a report with no crash in it.
    @Test func onlyACrash() throws {
        for (key, value) in [("is_fatal", false), ("is_clean_exit", true)] {
            var record = try Fixtures.record()
            var crash = try #require(record["crash"] as? [String: Any])
            var error = try #require(crash["error"] as? [String: Any])
            error[key] = value
            crash["error"] = error
            record["crash"] = crash
            #expect(CrashRecording.report(from: record) == nil)
        }
        var record = try Fixtures.record()
        record["crash"] = nil
        #expect(CrashRecording.report(from: record) == nil)
    }

    /// An NSException's and a C++ exception's name and reason; a bad
    /// access's signal, code and address where nothing says more.
    @Test func howItWasCaught() throws {
        func report(_ error: [String: Any]) throws -> CrashReport {
            var record = try Fixtures.record()
            var crash = try #require(record["crash"] as? [String: Any])
            crash["error"] = error
            record["crash"] = crash
            record["binary_images"] = nil
            return try #require(CrashRecording.report(from: record))
        }
        let exception = try report(["type": "nsexception", "reason": "*** -[__NSArrayM objectAtIndex:]: index 5 beyond bounds [0 .. 2]",
                                    "nsexception": ["name": "NSRangeException"]])
        #expect(exception.exceptionType == "NSRangeException")
        #expect(exception.reason == "*** -[__NSArrayM objectAtIndex:]: index 5 beyond bounds [0 .. 2]")
        #expect(exception.mechanism == "nsexception")

        let cpp = try report(["type": "cpp_exception", "reason": "vector", "cpp_exception": ["name": "std::out_of_range"]])
        #expect(cpp.exceptionType == "std::out_of_range")
        #expect(cpp.reason == "vector")
        #expect(cpp.mechanism == "cpp_exception")

        let access = try report(["type": "mach", "address": 16,
                                 "mach": ["exception_name": "EXC_BAD_ACCESS", "code_name": "KERN_INVALID_ADDRESS"],
                                 "signal": ["name": "SIGSEGV"]])
        #expect(access.exceptionType == "EXC_BAD_ACCESS")
        #expect(access.reason == "SIGSEGV, KERN_INVALID_ADDRESS at 0x10")

        let signal = try report(["type": "signal", "signal": ["name": "SIGABRT"]])
        #expect(signal.exceptionType == "SIGABRT")
        #expect(signal.reason == "SIGABRT")
        #expect(signal.mechanism == "signal")
    }

    /// Without the executable's name in the report, the one given (the
    /// running app's) decides which frames are the app's own; without the
    /// app's version, it's unknown.
    @Test func whatTheRecordLeavesOut() throws {
        var record = try Fixtures.record()
        var system = try #require(record["system"] as? [String: Any])
        for key in ["CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion", "machine", "system_name", "system_version"] {
            system[key] = nil
        }
        system["build_type"] = "simulator"
        record["system"] = system
        let given = try #require(CrashRecording.report(from: record, executable: "libswiftCore.dylib"))
        #expect(given.frames.map(\.inApp) == [true, true, true, true, false, false])
        #expect(given.appVersion == "")
        #expect(given.appBuild == "")
        #expect(given.system == "unknown")
        #expect(given.deviceModel == "unknown (Simulator)")
        // Else the process' name.
        let named = try #require(CrashRecording.report(from: record))
        #expect(named.frames.map(\.inApp) == [false, false, false, false, true, false])
    }

    @Test func timesAsTheRecorderWritesThem() {
        #expect(CrashRecording.date("2026-11-24T18:27:05Z") == Date(timeIntervalSince1970: 1_795_544_825))
        #expect(CrashRecording.date("2026-11-24T18:27:05.5Z") == Date(timeIntervalSince1970: 1_795_544_825.5))
        #expect(CrashRecording.date(1_795_544_825) == Date(timeIntervalSince1970: 1_795_544_825))
        #expect(CrashRecording.date("not a time") == nil)
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

    /// A public repository's signature leaves the reason out (its issue
    /// doesn't carry it): two reasons in the same image are one crash there,
    /// and two with every symbol sign as a private repository's do.
    @Test func withoutTheReasonTheReasonDecidesNothing() {
        var first = Fixtures.report(type: "EXC_BREAKPOINT")
        for index in first.frames.indices where first.frames[index].inApp { first.frames[index].symbol = nil }
        var second = first
        second.reason = "Example/List.swift:12: Fatal error: Unexpectedly found nil"
        #expect(first.signature != second.signature)
        #expect(first.signature(withReason: false) == second.signature(withReason: false))
        #expect(first.signature(withReason: false) != first.signature)
        #expect(first.signature(withReason: true) == first.signature)
        #expect(Fixtures.report(type: "EXC_BAD_ACCESS").signature(withReason: false) != first.signature(withReason: false))
        let symbols = Fixtures.report()
        #expect(symbols.signature(withReason: false) == symbols.signature)
    }
}
