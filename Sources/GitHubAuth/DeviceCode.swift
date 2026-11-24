import Foundation

/// The device flow's first answer: the code the user enters at
/// `verificationURI`, and how the app waits for them to.
public struct DeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expires: Date
    /// Seconds between asks.
    public let interval: Int

    public init(deviceCode: String, userCode: String, verificationURI: URL, expires: Date, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expires = expires
        self.interval = interval
    }
}
