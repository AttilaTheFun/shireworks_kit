/// Where signing in to GitHub stands: signed out; asking GitHub for a
/// code; the code shown, GitHub asked after it until the user has entered
/// it at github.com/login/device; or signed in (a token kept).
public enum SignInState: Equatable, Sendable {
    case signedOut
    case asking
    case entering(DeviceCode)
    case signedIn
}
