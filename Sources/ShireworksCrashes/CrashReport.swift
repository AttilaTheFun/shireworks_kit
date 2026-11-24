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
    /// The crash's own id (the crash reporter's event id).
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

        /// "MyApp + 0x1a2b", or the symbol where known: what names the frame
        /// in a title and a signature.
        public var location: String {
            if let symbol, !symbol.isEmpty, symbol != "<redacted>" { return symbol }
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

    static func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }
}

/// What makes two crashes the same: the exception's type and the top frames
/// (`CrashReport.topFrames`, the app's own where any is), each by its
/// symbol, or its image and offset where the device had no symbol. Not the
/// reason, which carries addresses that change from run to run.
///
/// Hashed with 64-bit FNV-1a, as 16 hex digits: the same on every platform
/// and in every process (unlike Swift's `Hasher`), with nothing to import.
/// Not a cryptographic hash, and needn't be: it tells an app's crashes
/// apart, not anyone's. A frame known only by its offset changes with the
/// build, so a crash without symbols has a signature per build.
public enum CrashSignature {
    /// How many frames go in.
    public static let frameCount = 3

    public static func of(_ report: CrashReport) -> String {
        let parts = [report.exceptionType] + report.topFrames.map(\.location)
        return fnv1a64(parts.joined(separator: "\n"))
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
