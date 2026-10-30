// story: e09s03
import Foundation

/// What AppModel needs from one TV, whatever the brand. Brand-only features
/// (The Frame Art Mode, Samsung app IDs) stay on the concrete client.
protocol TVController: Actor {
    func update(ip: String, isFrame: Bool) async
    func pair() async throws
    func forgetPairing() async
    func disconnectAll() async
    func sendKey(_ code: String) async throws
    func holdKey(_ code: String, seconds: Double) async throws
    func sendText(_ text: String, submit: Bool) async throws
    func powerOff() async throws
    /// Turns on a TV that still answers on the LAN in standby.
    func wakeFromStandby() async throws
}

/// TVs that list their apps by title (Sony, LG) instead of fixed Samsung IDs.
protocol NamedAppLauncher: TVController {
    func findApp(named name: String) async throws -> TVAppEntry?
    func launchApp(named name: String) async throws
    /// A raw id from a preset: Sony app URI or webOS app id.
    func launch(id: String) async throws
}
