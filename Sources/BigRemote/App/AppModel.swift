import AppKit
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
    @ObservationIgnored var clients: [String: SamsungTVClient] = [:]
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
                clients[tv.id] = SamsungTVClient(tv: tv) { [weak self] update in
                    Task { @MainActor in self?.apply(update, to: id) }
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
    func client(for tv: TVDevice) throws -> SamsungTVClient {
        guard let client = clients[tv.id] else { throw TVError.noTVSelected }
        return client
    }

    private func apply(_ update: TVClientUpdate, to id: String) {
        guard tvs.contains(where: { $0.id == id }) else { return }
        var status = statuses[id] ?? TVStatus()
        switch update {
        case .link(let link): status.link = link
        case .artMode(let mode): status.artMode = mode
        case .goingToStandby:
            status.artMode = nil
            status.reachability = .standby
        case .ime(let active): status.imeActive = active
        case .artAPIVersion(let version): status.artAPIVersion = version
        }
        statuses[id] = status
    }

    // MARK: - Polling (read-only REST, every 7 s)

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAll()
                try? await Task.sleep(for: .seconds(7))
            }
        }
    }

    func pollAll() async {
        let targets = tvs.map { ($0.id, $0.ip) }
        let rest = self.rest
        let results = await withTaskGroup(of: (String, TVRESTClient.InfoResult).self) { group in
            for (id, ip) in targets {
                group.addTask { (id, await rest.fetchDeviceInfo(ip: ip)) }
            }
            var collected: [(String, TVRESTClient.InfoResult)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (id, result) in results { applyInfo(result.info, to: id) }
        updateLocalNetworkHint(results.map(\.1))
    }

    /// All TVs failed with a "local network prohibited" style error while
    /// the Mac has a private IPv4 address: the permission is the likely cause.
    private func updateLocalNetworkHint(_ results: [TVRESTClient.InfoResult]) {
        guard !results.isEmpty else { localNetworkBlocked = false; return }
        let allDenied = results.allSatisfy { $0.looksLikeLocalNetworkDenied }
        let blocked = allDenied && !TVDiscovery.localIPv4Addresses().isEmpty
        if blocked != localNetworkBlocked { localNetworkBlocked = blocked }
    }

    func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func refresh(_ tv: TVDevice) async -> DeviceInfo? {
        let info = await rest.deviceInfo(ip: tv.ip)
        applyInfo(info, to: tv.id)
        return info
    }

    private func applyInfo(_ info: DeviceInfo?, to id: String) {
        guard tvs.contains(where: { $0.id == id }) else { return }
        guard let info else { return markUnreachable(id) }
        missedPolls[id] = 0
        var status = statuses[id] ?? TVStatus()
        if !info.isOn, status.reachability != .standby, !busyTVIDs.contains(id), let client = clients[id] {
            // Standby: the sockets are dead even if no close arrived.
            Task { await client.disconnectAll() }
        }
        status.info = info
        status.lastSeen = Date()
        status.reachability = info.isOn ? .on : .standby
        if !info.isOn { status.artMode = nil }
        statuses[id] = status
        fillMissingDetails(of: id, from: info)
        if info.isOn, let tv = tvs.first(where: { $0.id == id }), tv.isFrame, let client = clients[tv.id] {
            Task { await client.startArtMonitoring() }
        }
    }

    private func markUnreachable(_ id: String) {
        var status = statuses[id] ?? TVStatus()
        status.reachability = .unreachable
        status.artMode = nil
        statuses[id] = status
        // No TCP FIN when a TV drops off Wi-Fi: after two silent polls
        // (~14 s) close the sockets so the next command reconnects.
        let misses = (missedPolls[id] ?? 0) + 1
        missedPolls[id] = misses
        if misses == 2, !busyTVIDs.contains(id), let client = clients[id] {
            Task { await client.disconnectAll() }
        }
    }

    /// Copies model, DUID, network type, Frame flag and MAC from the device info.
    private func fillMissingDetails(of id: String, from info: DeviceInfo) {
        guard let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        var tv = tvs[index]
        if tv.duid == nil { tv.duid = info.duid }
        if tv.modelName == nil { tv.modelName = info.modelName }
        if tv.networkType != info.networkType, info.networkType != nil { tv.networkType = info.networkType }
        if info.isFrame { tv.isFrame = true }
        if tv.mac == nil {
            tv.mac = info.isWired ? ARPTable.mac(for: tv.ip) : info.wifiMac?.uppercased()
        }
        if tv != tvs[index] { tvs[index] = tv }
    }

    // MARK: - Feedback

    func show(_ message: String) {
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
                self.show(error.localizedDescription)
            }
        }
    }

    func requireTV() throws -> TVDevice {
        guard let tv = selectedTV else { throw TVError.noTVSelected }
        return tv
    }

}
