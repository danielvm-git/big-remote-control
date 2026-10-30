// story: e07s01
import Foundation

/// Adding, removing and discovering TVs.
extension AppModel {
    func addTV(ip: String) async {
        // pt-BR number pads type "192,168,0,20".
        let trimmed = ip.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard NetworkAddress.ipv4Octets(trimmed) != nil else { return show(TVError.invalidAddress.localizedDescription) }
        if tvs.contains(where: { $0.ip == trimmed }) { return show("Essa TV já está na lista.") }
        if let info = await rest.deviceInfo(ip: trimmed, timeout: 3) {
            add(info: info)
        } else if let info = await sonyREST.fetchDeviceInfo(ip: trimmed, timeout: 3).info {
            add(info: info)
        } else if let info = await lgREST.fetchDeviceInfo(ip: trimmed, timeout: 3).info {
            add(info: info)
        } else {
            let tv = TVDevice(id: "ip-\(trimmed)", name: "TV \(trimmed)", ip: trimmed)
            tvs.append(tv)
            show("TV adicionada sem resposta. Ela pode estar em espera.")
        }
    }

    func add(info: DeviceInfo) {
        guard !tvs.contains(where: { $0.ip == info.ip || ($0.duid != nil && $0.duid == info.duid) }) else {
            return show("Essa TV já está na lista.")
        }
        var tv = TVDevice.from(info: info)
        if tv.mac == nil, info.isWired || info.brand != .samsung { tv.mac = ARPTable.mac(for: info.ip) }
        tvs.append(tv)
        Log.info(.discovery, "tv.added", tv: tv.id, ["ip": tv.ip, "brand": tv.vendor.rawValue, "model": tv.modelName ?? "?"])
        if selectedTVID == nil { selectedTVID = tv.id }
        show("“\(tv.name)” adicionada.")
    }

    func remove(_ tv: TVDevice) {
        Log.info(.discovery, "tv.removed", tv: tv.id, ["ip": tv.ip])
        TokenStore().setToken(nil, for: TokenStore.key(for: tv))
        tvs.removeAll { $0.id == tv.id }
        statuses[tv.id] = nil
        if selectedTVID == tv.id { selectedTVID = tvs.first?.id }
    }

    func discover() {
        guard !isScanning else { return }
        isScanning = true
        discovered = []
        Task {
            let found = await TVDiscovery.scan()
            self.discovered = found
            self.isScanning = false
            Log.info(.discovery, "scan.done", ["found": found.map { "\($0.brand.rawValue)@\($0.ip)" }.joined(separator: ",")])
            if found.isEmpty {
                self.show(self.localNetworkBlocked
                    ? "Nenhuma TV encontrada. Permita Rede Local em Ajustes do Sistema > Privacidade e Segurança > Rede Local."
                    : "Nenhuma TV encontrada na rede.")
            } else {
                self.show("\(found.count) TV(s) encontrada(s).")
            }
        }
    }
}
