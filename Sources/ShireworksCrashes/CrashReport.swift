import Foundation

/// One crash of the app, as the next launch found it: what the app and the
/// device were, the exception, the crashing thread's frames (innermost
/// first, as a crash report reads), the other threads, the binary images
/// loaded, and the breadcrumbs left before it.
///
/// Frames are as the device could name them: an image and an address in it
/// always, a symbol where the device knew one. Each image's UUID and load
/// address go with it, so a frame can be symbolicated later against the
/// build's dSYMs (image + offset).
public struct CrashReport: Codable, Sendable, Equatable, Identifiable {
    /// The crash's own id (the crash recorder's report id).
    public var id: String
    /// When the app crashed.
    public var date: Date
    /// CFBundleShortVersionString and CFBundleVersion of the build that crashed.
    public var appVersion: String
    public var appBuild: String
    /// "macOS 27.2 (26C123)", "iOS 27.2".
    public var system: String
    /// The hardware model ("iPhone17,1", "Mac16,10").
    public var deviceModel: String
    /// "EXC_BAD_ACCESS", "EXC_BREAKPOINT", "NSInvalidArgumentException".
    public var exceptionType: String
    /// What the exception said: its reason, or the signal and its codes.
    public var reason: String
    /// How it was caught: "mach", "signal", "nsexception", "cpp_exception".
    public var mechanism: String?
    /// The crashing thread, innermost frame first.
    public var frames: [Frame]
    /// The other threads, as they were.
    public var threads: [Thread]?
    /// The binary images loaded.
    public var images: [Image]
    /// What happened before it, oldest first, a short line each.
    public var breadcrumbs: [String]?

    public init(id: String, date: Date, appVersion: String, appBuild: String, system: String, deviceModel: String,
                exceptionType: String, reason: String, mechanism: String? = nil, frames: [Frame],
                threads: [Thread]? = nil, images: [Image] = [], breadcrumbs: [String]? = nil) {
        self.id = id
        self.date = date
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.system = system
        self.deviceModel = deviceModel
        self.exceptionType = exceptionType
        self.reason = reason
        self.mechanism = mechanism
        self.frames = frames
        self.threads = threads
        self.images = images
        self.breadcrumbs = breadcrumbs
    }

    /// One frame of a thread: the image it was in and the address, and the
    /// symbol where the device knew one.
    public struct Frame: Codable, Sendable, Equatable {
        /// The image's file name ("MyApp", "libswiftCore.dylib"): never its path.
        public var imageName: String?
        public var imageUUID: String?
        public var instructionAddress: UInt64
        /// Where the image was loaded.
        public var imageAddress: UInt64?
        /// The function, where the device could name it.
        public var symbol: String?
        /// Whether the frame is the app's own code (not a system library's).
        public var inApp: Bool

        public init(imageName: String?, imageUUID: String? = nil, instructionAddress: UInt64, imageAddress: UInt64? = nil,
                    symbol: String? = nil, inApp: Bool = false) {
            self.imageName = imageName
            self.imageUUID = imageUUID
            self.instructionAddress = instructionAddress
            self.imageAddress = imageAddress
            self.symbol = symbol
            self.inApp = inApp
        }

        /// The address's offset in its image, what symbolication takes; nil
        /// where the image isn't known.
        public var offset: UInt64? {
            guard let imageAddress, imageAddress <= instructionAddress else { return nil }
            return instructionAddress - imageAddress
        }

        /// Its symbol, where the device had one. Not one that names no
        /// function: `<redacted>` (a symbol hidden), or the executable's own
        /// header (`_mh_execute_header`, what the nearest exported symbol of
        /// a stripped executable is).
        public var symbolName: String? {
            guard let symbol, !symbol.isEmpty, !["<redacted>", "_mh_execute_header", "__mh_execute_header"].contains(symbol)
            else { return nil }
            return symbol
        }

        /// "MyApp + 0x1a2b", or the symbol where known: what names the frame
        /// in a title and a signature.
        public var location: String {
            if let symbolName { return symbolName }
            let image = imageName ?? "?"
            guard let offset else { return image + " " + CrashReport.hex(instructionAddress) }
            return image + " + " + CrashReport.hex(offset)
        }
    }

    /// A thread other than the crashing one.
    public struct Thread: Codable, Sendable, Equatable {
        public var id: Int?
        public var name: String?
        public var frames: [Frame]

        public init(id: Int?, name: String? = nil, frames: [Frame]) {
            self.id = id
            self.name = name
            self.frames = frames
        }
    }

    /// A binary image the app had loaded: what symbolicates its frames.
    public struct Image: Codable, Sendable, Equatable {
        public var name: String
        public var uuid: String?
        public var address: UInt64
        public var size: UInt64?

        public init(name: String, uuid: String? = nil, address: UInt64, size: UInt64? = nil) {
            self.name = name
            self.uuid = uuid
            self.address = address
            self.size = size
        }
    }

    /// The frames that name the crash: the app's own nearest the top, or the
    /// top frames where none is the app's.
    public var topFrames: [Frame] {
        let own = frames.filter(\.inApp)
        return Array((own.isEmpty ? frames : own).prefix(CrashSignature.frameCount))
    }

    /// The same crash, wherever and whenever it happens (`CrashSignature`):
    /// what finds its issue.
    public var signature: String { CrashSignature.of(self) }

    /// The signature an issue is filed under: with the reason (`signature`)
    /// where its details go in, without it where they're left out (a public
    /// repository's, `CrashSignature.of(_:withReason:)`).
    public func signature(withReason: Bool) -> String { CrashSignature.of(self, withReason: withReason) }

    static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
}

/// What makes two crashes the same: the exception's type and the top frames
/// (`CrashReport.topFrames`, the app's own where any is), each by its
/// symbol. Not the reason, which carries addresses that change from run to
/// run.
///
/// Where a top frame has no symbol (a release build's own frames: the device
/// has none, and an offset moves with every build), the signature is kept
/// the same from build to build instead: the exception's type, its reason
/// with its addresses and numbers taken out, and each such frame by its
/// image alone. That can take two crashes in the same image for one (each
/// occurrence's comment carries its own crashing thread), rather than making
/// a new issue of the same crash at every build.
///
/// Without the reason (`withReason` false: a public repository's issue, which
/// leaves the reason out), that path takes the exception's type and the
/// frames alone, so a crash is never found by text its issue doesn't carry.
/// Where every top frame has a symbol the two are the same; where one hasn't,
/// a public repository's signature differs from a private one's, and a
/// repository made public (or private) may open a crash's issue again, once.
///
/// Hashed with 64-bit FNV-1a, as 16 hex digits: the same on every platform
/// and in every process (unlike Swift's `Hasher`), with nothing to import.
/// Not a cryptographic hash, and needn't be: it tells an app's crashes
/// apart, not anyone's.
public enum CrashSignature {
    /// How many frames go in.
    public static let frameCount = 3

    public static func of(_ report: CrashReport, withReason: Bool = true) -> String {
        let frames = report.topFrames
        let parts: [String]
        if frames.allSatisfy({ $0.symbolName != nil }) {
            parts = [report.exceptionType] + frames.map(\.location)
        } else {
            let reason = withReason ? [steady(report.reason)] : []
            parts = [report.exceptionType] + reason + frames.map { $0.symbolName ?? ($0.imageName ?? "?") }
        }
        return fnv1a64(parts.joined(separator: "\n"))
    }

    /// A reason without what changes from one run (or build) to the next:
    /// each run of hex digits after `0x`, and each run of digits, made `#`
    /// (`KERN_INVALID_ADDRESS at 0x10` and `at 0x28` are the same; so are
    /// `Foo.swift:12` and `Foo.swift:14`, a line moved by an edit).
    static func steady(_ reason: String?) -> String {
        var out = "", chars = Array(reason ?? ""), index = 0
        while index < chars.count {
            if chars[index] == "0", index + 1 < chars.count, chars[index + 1] == "x" || chars[index + 1] == "X" {
                index += 2
                while index < chars.count, chars[index].isHexDigit { index += 1 }
                out += "#"
            } else if chars[index].isNumber {
                while index < chars.count, chars[index].isNumber { index += 1 }
                out += "#"
            } else {
                out.append(chars[index])
                index += 1
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 64-bit FNV-1a of the text's UTF-8, as 16 lowercase hex digits.
    static func fnv1a64(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
