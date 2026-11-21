import Foundation
import Security
@main struct KeychainStartupCheck {
    static func main() {
        var previous: DarwinBoolean = true
        precondition(SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess)
        let start = Date()
        do { _ = try SoulseekKeychain.load(allowInteraction: false); print("Noninteractive Keychain read returned") }
        catch { print("Noninteractive Keychain read returned status", (error as NSError).code) }
        var restored: DarwinBoolean = true
        precondition(SecKeychainGetUserInteractionAllowed(&restored) == errSecSuccess && restored.boolValue == previous.boolValue, "Keychain UI policy was not restored")
        precondition(Date().timeIntervalSince(start) < 5, "Startup Keychain read blocked")
    }
}
