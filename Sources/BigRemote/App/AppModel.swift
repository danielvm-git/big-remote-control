import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // MARK: Persisted state

    var tvs: [TVDevice] { didSet { settings.tvs = tvs; syncClients() } }
    var selectedTVID: String? { didSet { settings.selectedTVID = selectedTVID } }
    var presets: [Preset] { didSet { presetStore.save(presets) } }
    var favoriteAppIDs: [String] { didSet { settings.favoriteAppIDs = favoriteAppIDs } }
    var customApps: [TVApp] { didSet { settings.customApps = customApps } }

    // MARK: Live state

    var statuses: [String: TVStatus] = [:]
    var banner: String?
    var discovered: [DeviceInfo] = []
    var isScanning = false
    var runningPresetID: UUID?
    var busyTVIDs: Set<String> = []
    /// True when every TV fails in a way that looks like the macOS Local
    /// Network permission is denied (not like TVs that are off).
    var localNetworkBlocked = false

    // SmartThings
    var smartThingsConfigured: Bool
    var stDevices: [STDevice] = []
    var stStatus: [String: STDeviceStatus] = [:]
    var stError: String?
    var stLoading = false

    // MARK: Internals

    @ObservationIgnored let settings = SettingsStore()
    @ObservationIgnored let presetStore = PresetStore()
    @ObservationIgnored let keychain = KeychainStore()
    @ObservationIgnored let rest = TVRESTClient()
    @ObservationIgnored let sonyREST = SonyRESTClient()
    @ObservationIgnored let lgREST = LGRESTClient()
    @ObservationIgnored var clients: [String: any TVController] = [:]
    @ObservationIgnored var pollTask: Task<Void, Never>?
    @ObservationIgnored var bannerTask: Task<Void, Never>?
    @ObservationIgnored var smartThingsToken: String?
    @ObservationIgnored var playToggle = false
    @ObservationIgnored var textDebounce: Task<Void, Never>?
    @ObservationIgnored var lastLiveText = ""
    /// Per-client chain so ip/isFrame updates reach the actor in order.
    @ObservationIgnored var updateTasks: [String: Task<Void, Never>] = [:]
    /// tvID -> (catalogue appID -> the ID that REST found installed).
    @ObservationIgnored var resolvedAppIDs: [String: [String: String]] = [:]
    /// Consecutive polls without a REST answer, per TV.
    @ObservationIgnored var missedPolls: [String: Int] = [:]

    static let smartThingsAccount = "smartthings-token"

    init() {
        let settings = SettingsStore()
        tvs = settings.tvs
        presets = PresetStore().load()
        favoriteAppIDs = settings.favoriteAppIDs
        customApps = settings.customApps
        smartThingsConfigured = settings.smartThingsConfigured
        let stored = settings.selectedTVID
        selectedTVID = settings.tvs.contains { $0.id == stored } ? stored : settings.tvs.first?.id
        let info = Bundle.main.infoDictionary
        Log.info(.app, "app.start", [
            "version": info?["CFBundleShortVersionString"] as? String ?? "?",
            "build": info?["CFBundleVersion"] as? String ?? "?",
            "platform": Log.device,
            "tvs": settings.tvs.map { "\($0.id)=\($0.vendor.rawValue)" }.joined(separator: ","),
        ])
        syncClients()
        startPolling()
    }

    // MARK: - Selection

    var selectedTV: TVDevice? { tvs.first { $0.id == selectedTVID } }

    func status(of tv: TVDevice) -> TVStatus { statuses[tv.id] ?? TVStatus() }

    var selectedStatus: TVStatus { selectedTV.map(status(of:)) ?? TVStatus() }

    var allApps: [TVApp] { TVApp.catalog + customApps }

    var favoriteApps: [TVApp] {
        favoriteAppIDs.compactMap { id in allApps.first { $0.appID == id } }
    }

    // MARK: - Clients

    private func syncClients() {
        for tv in tvs {
            if let client = clients[tv.id] {
                let ip = tv.ip, frame = tv.isFrame
                let previous = updateTasks[tv.id]
                updateTasks[tv.id] = Task {
                    await previous?.value
                    await client.update(ip: ip, isFrame: frame)
                }
            } else {
                let id = tv.id
                let onUpdate: @Sendable (TVClientUpdate) -> Void = { [weak self] update in
                    Task { @MainActor in self?.apply(update, to: id) }
                }
                switch tv.vendor {
                case .samsung: clients[tv.id] = SamsungTVClient(tv: tv, onUpdate: onUpdate)
                case .sony: clients[tv.id] = SonyTVClient(tv: tv, onUpdate: onUpdate)
                case .lg: clients[tv.id] = LGTVClient(tv: tv, onUpdate: onUpdate)
                }
            }
        }
        for id in clients.keys where !tvs.contains(where: { $0.id == id }) {
            let client = clients.removeValue(forKey: id)
            let previous = updateTasks.removeValue(forKey: id)
            resolvedAppIDs[id] = nil
            missedPolls[id] = nil
            Task {
                await previous?.value
                await client?.disconnectAll()
            }
        }
    }

    /// Throws when the TV was removed (e.g. during a wake wait or a preset).
    func client(for tv: TVDevice) throws -> any TVController {
        guard let client = clients[tv.id] else { throw TVError.noTVSelected }
        return client
    }

    private func apply(_ update: TVClientUpdate, to id: String) {
        guard tvs.contains(where: { $0.id == id }) else { return }
        var status = statuses[id] ?? TVStatus()
        switch update {
        case .link(let link):
            if status.link != link { Log.info(.link, "link.changed", tv: id, ["from": status.link.label, "to": link.label]) }
            status.link = link
        case .artMode(let mode): status.artMode = mode
        case .goingToStandby:
            status.artMode = nil
            status.reachability = .standby
        case .ime(let active): status.imeActive = active
        case .artAPIVersion(let version): status.artAPIVersion = version
        }
        statuses[id] = status
    }

    // MARK: - Feedback

    func show(_ message: String) {
        Log.info(.app, "banner", ["text": message])
        banner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch is CancellationError {
            } catch {
                Log.error(.command, "action.error", ["error": error.localizedDescription])
                self.show(error.localizedDescription)
            }
        }
    }

    func requireTV() throws -> TVDevice {
        guard let tv = selectedTV else { throw TVError.noTVSelected }
        return tv
    }

    /// Art Mode and Samsung app IDs exist only on the Samsung client.
    func samsungClient(for tv: TVDevice) throws -> SamsungTVClient {
        guard let client = try client(for: tv) as? SamsungTVClient else { throw TVError.notFrame }
        return client
    }

    func sonyClient(for tv: TVDevice) throws -> SonyTVClient {
        guard let client = try client(for: tv) as? SonyTVClient else { throw TVError.noTVSelected }
        return client
    }

    /// Sony and LG: apps launch by title.
    func namedAppClient(for tv: TVDevice) throws -> (any NamedAppLauncher)? {
        try client(for: tv) as? any NamedAppLauncher
    }

}
