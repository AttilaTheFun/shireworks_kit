// What the tests read: a crash as the crash recorder hands it over (a Swift
// "Index out of range" in a Mac app, KSCrash's report as it wrote it on a
// macOS VM, its registers and stack dumps and some threads taken out and the
// app named Example), and a report made by hand.

import Foundation
@testable import ShireworksCrashes

enum Fixtures {
    /// KSCrash's report: frames innermost first, with the symbols the
    /// device had; addresses as numbers; the time in ISO 8601 to the
    /// microsecond; the Swift runtime's message beside libswiftCore's image;
    /// a thread with no frame (the recorder's own, as it wrote).
    static let indexOutOfRange = #"""
    {
      "binary_images": [
        {
          "image_addr": 4369481728,
          "image_size": 409600,
          "image_vmaddr": 4294967296,
          "name": "/Applications/Example.app/Contents/MacOS/Example",
          "uuid": "1C2B3187-191D-3AA4-A387-77B4336C4EF9"
        },
        {
          "image_addr": 6644289536,
          "image_size": 535716,
          "image_vmaddr": 6449876992,
          "name": "/usr/lib/system/libsystem_c.dylib",
          "uuid": "FBA7B23E-AA60-3A90-9AA4-A7A2E0AD63EE"
        },
        {
          "image_addr": 6645547008,
          "image_size": 256428,
          "image_vmaddr": 6451134464,
          "name": "/usr/lib/system/libsystem_kernel.dylib",
          "uuid": "F63BF418-8F75-34A4-AAF1-8CAF2B9B6A05"
        },
        {
          "image_addr": 6645805056,
          "image_size": 51484,
          "image_vmaddr": 6451392512,
          "name": "/usr/lib/system/libsystem_pthread.dylib",
          "uuid": "5A1828C3-CBC2-3B85-BD07-C8ED10021A41"
        },
        {
          "crash_info_message": "Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range\n",
          "image_addr": 6987055104,
          "image_size": 5869104,
          "image_vmaddr": 6792642560,
          "name": "/usr/lib/swift/libswiftCore.dylib",
          "uuid": "C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0"
        },
        {
          "image_addr": 6641606656,
          "image_size": 784100,
          "image_vmaddr": 6447194112,
          "name": "/usr/lib/dyld",
          "uuid": "D341DDCB-7969-3A9C-8E03-0CF4751398A9"
        }
      ],
      "crash": {
        "error": {
          "address": 6988502380,
          "is_clean_exit": false,
          "is_fatal": true,
          "mach": {
            "code": 1,
            "code_name": "KERN_INVALID_ADDRESS",
            "exception": 6,
            "exception_name": "EXC_BREAKPOINT",
            "subcode": 6988502380
          },
          "signal": {
            "code": 0,
            "code_name": "0",
            "name": "SIGTRAP",
            "signal": 5
          },
          "type": "mach"
        },
        "threads": [
          {
            "backtrace": {
              "contents": [
                {
                  "instruction_addr": 6988502380,
                  "object_addr": 6987055104,
                  "object_name": "libswiftCore.dylib",
                  "object_uuid": "C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0",
                  "symbol_addr": 6988502012,
                  "symbol_name": "$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtFySRys5UInt8VGXEfU_yAMXEfU_"
                },
                {
                  "instruction_addr": 6988502380,
                  "object_addr": 6987055104,
                  "object_name": "libswiftCore.dylib",
                  "object_uuid": "C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0",
                  "symbol_addr": 6988502012,
                  "symbol_name": "$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtFySRys5UInt8VGXEfU_yAMXEfU_"
                },
                {
                  "instruction_addr": 6987115240,
                  "object_addr": 6987055104,
                  "object_name": "libswiftCore.dylib",
                  "object_uuid": "C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0",
                  "symbol_addr": 6987115080,
                  "symbol_name": "$sSa15_checkSubscript_20wasNativeTypeCheckeds16_DependenceTokenVSi_SbtF"
                },
                {
                  "instruction_addr": 6987276240,
                  "object_addr": 6987055104,
                  "object_name": "libswiftCore.dylib",
                  "object_uuid": "C9B36DA7-BB34-35AF-BC5D-91ECBCAA9ED0",
                  "symbol_addr": 6987276152,
                  "symbol_name": "$sSayxSicig"
                },
                {
                  "instruction_addr": 4369489296,
                  "object_addr": 4369481728,
                  "object_name": "Example",
                  "object_uuid": "1C2B3187-191D-3AA4-A387-77B4336C4EF9",
                  "symbol_addr": 4369486848,
                  "symbol_name": "main"
                },
                {
                  "instruction_addr": 6641811072,
                  "object_addr": 6641606656,
                  "object_name": "dyld",
                  "object_uuid": "D341DDCB-7969-3A9C-8E03-0CF4751398A9",
                  "symbol_addr": 6641804384,
                  "symbol_name": "start"
                }
              ],
              "skipped": 0
            },
            "crashed": true,
            "current_thread": false,
            "index": 0,
            "state": "TH_STATE_WAITING"
          },
          {
            "backtrace": {
              "contents": [
                {
                  "instruction_addr": 6645564168,
                  "object_addr": 6645547008,
                  "object_name": "libsystem_kernel.dylib",
                  "object_uuid": "F63BF418-8F75-34A4-AAF1-8CAF2B9B6A05",
                  "symbol_addr": 6645564160,
                  "symbol_name": "__semwait_signal"
                },
                {
                  "instruction_addr": 6644346964,
                  "object_addr": 6644289536,
                  "object_name": "libsystem_c.dylib",
                  "object_uuid": "FBA7B23E-AA60-3A90-9AA4-A7A2E0AD63EE",
                  "symbol_addr": 6644346744,
                  "symbol_name": "nanosleep"
                },
                {
                  "instruction_addr": 6644387464,
                  "object_addr": 6644289536,
                  "object_name": "libsystem_c.dylib",
                  "object_uuid": "FBA7B23E-AA60-3A90-9AA4-A7A2E0AD63EE",
                  "symbol_addr": 6644387412,
                  "symbol_name": "sleep"
                },
                {
                  "instruction_addr": 4369608620,
                  "object_addr": 4369481728,
                  "object_name": "Example",
                  "object_uuid": "1C2B3187-191D-3AA4-A387-77B4336C4EF9",
                  "symbol_addr": 4369608508,
                  "symbol_name": "monitorThreadCache"
                },
                {
                  "instruction_addr": 6645832960,
                  "object_addr": 6645805056,
                  "object_name": "libsystem_pthread.dylib",
                  "object_uuid": "5A1828C3-CBC2-3B85-BD07-C8ED10021A41",
                  "symbol_addr": 6645832824,
                  "symbol_name": "_pthread_start"
                },
                {
                  "instruction_addr": 6645812460,
                  "object_addr": 6645805056,
                  "object_name": "libsystem_pthread.dylib",
                  "object_uuid": "5A1828C3-CBC2-3B85-BD07-C8ED10021A41",
                  "symbol_addr": 6645812452,
                  "symbol_name": "thread_start"
                }
              ],
              "skipped": 0
            },
            "crashed": false,
            "current_thread": false,
            "index": 1,
            "state": "TH_STATE_WAITING"
          },
          {
            "backtrace": {
              "contents": [],
              "skipped": 0
            },
            "crashed": false,
            "current_thread": true,
            "index": 3,
            "state": "TH_STATE_RUNNING"
          }
        ]
      },
      "debug": {},
      "process": {},
      "report": {
        "id": "84F501DB-DE74-4B02-817D-343BAB6B2E6E",
        "monitor_id": "MachException",
        "process_name": "Example",
        "run_id": "e4c5ef5f-e67e-4e95-872c-8ef04dda32cd",
        "timestamp": "2026-11-24T18:27:05.779506Z",
        "type": "standard",
        "version": "3.9.0"
      },
      "system": {
        "CFBundleExecutable": "Example",
        "CFBundleExecutablePath": "/Applications/Example.app/Example",
        "CFBundleIdentifier": "com.example.app",
        "CFBundleName": "Example",
        "CFBundleShortVersionString": "1.2.0",
        "CFBundleVersion": "42",
        "app_start_time": "2026-11-24T18:27:05Z",
        "app_uuid": "1C2B3187-191D-3AA4-A387-77B4336C4EF9",
        "binary_arch": "arm64",
        "build_type": "debug",
        "cpu_arch": "arm64e",
        "kernel_version": "Darwin Kernel Version 27.0.0: Tue Aug 11 21:00:07 PDT 2026; root:xnu-13432.1.9~1/RELEASE_ARM64_VMAPPLE",
        "machine": "VirtualMac2,1",
        "os_version": "26A434",
        "process_name": "Example",
        "system_name": "macOS",
        "system_version": "27.0.1",
        "time_zone": "EST"
      },
      "user": {}
    }
    """#

    static func record(_ json: String = indexOutOfRange) throws -> [String: Any] {
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
