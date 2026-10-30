// story: e04s01 e07s01
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Read-only status polling (every 7 s) and how its answers update the UI state.
extension AppModel {
    func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAll()
                try? await Task.sleep(for: .seconds(7))
            }
        }
    }

    func pollAll() async {
        let targets = tvs.map { ($0.id, $0.ip, $0.vendor) }
        let rest = self.rest, sony = self.sonyREST, lg = self.lgREST
        let results = await withTaskGroup(of: (String, TVRESTClient.InfoResult).self) { group in
            for (id, ip, brand) in targets {
                group.addTask {
                    switch brand {
                    case .samsung: return (id, await rest.fetchDeviceInfo(ip: ip))
                    case .sony: return (id, await sony.fetchDeviceInfo(ip: ip))
                    case .lg: return (id, await lg.fetchDeviceInfo(ip: ip))
                    }
                }
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
    func updateLocalNetworkHint(_ results: [TVRESTClient.InfoResult]) {
        guard !results.isEmpty else { localNetworkBlocked = false; return }
        let allDenied = results.allSatisfy { $0.looksLikeLocalNetworkDenied }
        let blocked = allDenied && !TVDiscovery.localIPv4Addresses().isEmpty
        if blocked != localNetworkBlocked { localNetworkBlocked = blocked }
    }

    func openLocalNetworkSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
        #else
        // iOS has no deep link to Local Network: the app's own Settings page holds the switch.
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }

    @discardableResult
    func refresh(_ tv: TVDevice) async -> DeviceInfo? {
        let info: DeviceInfo? = switch tv.vendor {
        case .samsung: await rest.deviceInfo(ip: tv.ip)
        case .sony: await sonyREST.fetchDeviceInfo(ip: tv.ip).info
        case .lg: await lgREST.fetchDeviceInfo(ip: tv.ip).info
        }
        applyInfo(info, to: tv.id)
        return info
    }

    func applyInfo(_ info: DeviceInfo?, to id: String) {
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
        let reachability: Reachability = info.isOn ? .on : .standby
        if status.reachability != reachability {
            Log.info(.poll, "reachability.changed", tv: id, ["from": "\(status.reachability)", "to": "\(reachability)"])
        }
        status.reachability = reachability
        if !info.isOn { status.artMode = nil }
        statuses[id] = status
        fillMissingDetails(of: id, from: info)
        if info.isOn, let tv = tvs.first(where: { $0.id == id }), tv.isFrame, let client = clients[tv.id] as? SamsungTVClient {
            Task { await client.startArtMonitoring() }
        }
    }

    func markUnreachable(_ id: String) {
        var status = statuses[id] ?? TVStatus()
        if status.reachability != .unreachable {
            Log.warning(.poll, "reachability.changed", tv: id, ["from": "\(status.reachability)", "to": "unreachable"])
        }
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
    func fillMissingDetails(of id: String, from info: DeviceInfo) {
        guard let index = tvs.firstIndex(where: { $0.id == id }) else { return }
        var tv = tvs[index]
        if tv.duid == nil { tv.duid = info.duid }
        if tv.modelName == nil { tv.modelName = info.modelName }
        if tv.networkType != info.networkType, info.networkType != nil { tv.networkType = info.networkType }
        if info.isFrame { tv.isFrame = true }
        if tv.mac == nil {
            // Sony and LG report no MAC without auth: ARP has it once the TV answered.
            tv.mac = info.isWired || info.brand != .samsung ? ARPTable.mac(for: tv.ip) : info.wifiMac?.uppercased()
        }
        if tv != tvs[index] { tvs[index] = tv }
    }
}
