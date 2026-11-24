// What the tests read: a crash as the crash reporter hands it over (a Swift
// "Index out of range" on a Mac, its event's JSON as Sentry's SDK serializes
// it, cut down to a few frames and images, a thread whose one frame is at 0
// as a real one had), and a report made by hand.

import Foundation
@testable import ShireworksCrashes

enum Fixtures {
    /// The event's JSON: frames outermost first, addresses as hex strings,
    /// the time in seconds since 1970, the breadcrumbs' in ISO 8601.
    static let indexOutOfRange = #"""
    {
      "event_id": "7d1b8e2c4f6a4b0e9c3d5a7f1e2b4c6d",
      "timestamp": 1793526060.25,
      "level": "fatal",
      "platform": "cocoa",
      "release": "com.example.app@1.2.0+42",
      "dist": "42",
      "environment": "production",
      "exception": {
        "values": [
          {
            "type": "EXC_BREAKPOINT",
            "value": "Exception 1, Code 6442452992, Subcode 8 > Fatal error: Index out of range in /Users/someone/Example/Sources/List.swift",
            "mechanism": {
              "type": "mach",
              "handled": false,
              "meta": {"signal": {"number": 5, "code": 0, "name": "SIGTRAP"}, "mach_exception": {"exception": 6, "code": 1, "subcode": 6442452992, "name": "EXC_BREAKPOINT"}}
            },
            "thread_id": 0
          }
        ]
      },
      "threads": {
        "values": [
          {
            "id": 0,
            "crashed": true,
            "current": true,
            "name": "main",
            "stacktrace": {
              "frames": [
                {"function": "start", "package": "/usr/lib/dyld", "image_addr": "0x0000000180000000", "instruction_addr": "0x0000000180012345", "symbol_addr": "0x0000000180012000", "in_app": false},
                {"function": "main", "package": "/Users/someone/Example/.build/debug/Example", "image_addr": "0x0000000100000000", "instruction_addr": "0x0000000100003f20", "symbol_addr": "0x0000000100003f00", "in_app": true},
                {"function": "<redacted>", "package": "/Users/someone/Example/.build/debug/Example", "image_addr": "0x0000000100000000", "instruction_addr": "0x0000000100001a2b", "in_app": true},
                {"function": "$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAESus6UInt32VtF", "package": "/usr/lib/swift/libswiftCore.dylib", "image_addr": "0x0000000190000000", "instruction_addr": "0x0000000190123456", "in_app": false}
              ]
            }
          },
          {
            "id": 1,
            "crashed": false,
            "current": false,
            "stacktrace": {
              "frames": [
                {"function": "start_wqthread", "package": "/usr/lib/system/libsystem_pthread.dylib", "image_addr": "0x000000018b000000", "instruction_addr": "0x000000018b001234", "in_app": false},
                {"function": "__workq_kernreturn", "package": "/usr/lib/system/libsystem_kernel.dylib", "image_addr": "0x000000018a000000", "instruction_addr": "0x000000018a001000", "in_app": false}
              ]
            }
          },
          {
            "id": 2,
            "crashed": false,
            "current": false,
            "stacktrace": {"frames": [{"image_addr": "0x0000000000000000", "instruction_addr": "0x0000000000000000", "in_app": false}]}
          }
        ]
      },
      "debug_meta": {
        "images": [
          {"type": "macho", "debug_id": "8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9", "code_file": "/Users/someone/Example/.build/debug/Example", "image_addr": "0x0000000100000000", "image_size": 65536, "image_vmaddr": "0x0000000100000000", "arch": "arm64"},
          {"type": "macho", "debug_id": "11111111-2222-3333-4444-555555555555", "code_file": "/usr/lib/swift/libswiftCore.dylib", "image_addr": "0x0000000190000000", "image_size": 4194304, "image_vmaddr": "0x0000000000000000", "arch": "arm64e"},
          {"type": "macho", "debug_id": "66666666-7777-8888-9999-aaaaaaaaaaaa", "code_file": "/usr/lib/dyld", "image_addr": "0x0000000180000000", "image_size": 655360, "arch": "arm64e"},
          {"type": "macho", "debug_id": "bbbbbbbb-cccc-dddd-eeee-ffffffffffff", "code_file": "/usr/lib/system/libsystem_kernel.dylib", "image_addr": "0x000000018a000000", "image_size": 245760, "arch": "arm64e"}
        ]
      },
      "contexts": {
        "app": {"app_identifier": "com.example.app", "app_name": "Example", "app_version": "1.2.0", "app_build": "42", "build_type": "simulator"},
        "os": {"name": "macOS", "version": "27.2", "build": "27C5000", "kernel_version": "Darwin Kernel Version 27.2.0", "rooted": false},
        "device": {"model": "Mac16,10", "family": "macOS", "arch": "arm64e", "simulator": false, "memory_size": 17179869184}
      },
      "breadcrumbs": [
        {"timestamp": "2026-11-01T09:40:58.123Z", "category": "started", "message": "Breadcrumb Tracking", "type": "debug", "level": "info"},
        {"timestamp": "2026-11-01T09:40:59.000Z", "category": "app.lifecycle", "type": "navigation", "level": "info", "data": {"state": "foreground"}}
      ]
    }
    """#

    static func event(_ json: String = indexOutOfRange) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
    }

    /// A crash in the app's own code, made by hand: `inApp`'s symbol and
    /// the exception's type are what its signature takes.
    static func report(id: String = "crash-1", version: String = "1.2.0", build: String = "42",
                       type: String = "EXC_BAD_ACCESS", inApp: String = "Example.List.item(at:)",
                       date: Date = Date(timeIntervalSince1970: 1_793_526_060)) -> CrashReport {
        CrashReport(
            id: id, date: date, appVersion: version, appBuild: build, system: "iOS 27.2", deviceModel: "iPhone17,1",
            exceptionType: type, reason: "KERN_INVALID_ADDRESS at 0x0000000000000010", mechanism: "mach",
            frames: [
                .init(imageName: "libswiftCore.dylib", instructionAddress: 0x1_9012_3456, imageAddress: 0x1_9000_0000,
                      symbol: "swift_retain"),
                .init(imageName: "Example", imageUUID: "8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9", instructionAddress: 0x1_0000_1a2b,
                      imageAddress: 0x1_0000_0000, symbol: inApp, inApp: true),
                .init(imageName: "Example", instructionAddress: 0x1_0000_3f20, imageAddress: 0x1_0000_0000, symbol: "main", inApp: true),
            ],
            threads: [.init(id: 1, name: "worker", frames: [
                .init(imageName: "libsystem_kernel.dylib", instructionAddress: 0x1_8a00_1000, imageAddress: 0x1_8a00_0000),
            ])],
            images: [
                .init(name: "Example", uuid: "8a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9", address: 0x1_0000_0000, size: 65536),
                .init(name: "libswiftCore.dylib", address: 0x1_9000_0000),
            ],
            breadcrumbs: ["09:40:59 [app.lifecycle] (state: foreground)"])
    }

    /// A folder of its own, made empty.
    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ShireworksCrashesTests-" + UUID().uuidString, isDirectory: true)
    }
}
