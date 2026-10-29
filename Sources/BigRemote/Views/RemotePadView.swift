import SwiftUI

/// Volume, channel, D-pad + OK, back/home/source/play.
struct RemotePadView: View {
    @Environment(AppModel.self) private var model
    var scale: CGFloat = 1

    private var small: CGFloat { 34 * scale }
    private var pad: CGFloat { 40 * scale }

    var body: some View {
        VStack(spacing: 12 * scale) {
            HStack(alignment: .center, spacing: 14 * scale) {
                rocker(up: .volumeUp, down: .volumeDown, upSymbol: "speaker.plus", downSymbol: "speaker.minus", title: "VOL")
                dpad
                rocker(up: .channelUp, down: .channelDown, upSymbol: "chevron.up", downSymbol: "chevron.down", title: "CH")
            }
            HStack(spacing: 10 * scale) {
                KeyButton(key: .back, symbol: "arrow.uturn.backward", size: small)
                KeyButton(key: .home, symbol: "house", size: small)
                KeyButton(key: .source, symbol: "rectangle.on.rectangle", size: small)
                Button { model.playPause() } label: { Image(systemName: "playpause") }
                    .buttonStyle(PadButtonStyle(size: small))
                    .help("Play / Pausa (alterna KEY_PLAY e KEY_PAUSE)")
                KeyButton(key: .mute, symbol: "speaker.slash", size: small)
            }
        }
    }

    private var dpad: some View {
        Grid(horizontalSpacing: 4 * scale, verticalSpacing: 4 * scale) {
            GridRow {
                Color.clear.frame(width: pad, height: pad)
                KeyButton(key: .up, symbol: "chevron.up", size: pad)
                Color.clear.frame(width: pad, height: pad)
            }
            GridRow {
                KeyButton(key: .left, symbol: "chevron.left", size: pad)
                Button { model.press(.enter) } label: { Text("OK").font(.system(size: pad * 0.34, weight: .bold)) }
                    .buttonStyle(PadButtonStyle(size: pad, prominent: true))
                    .help("OK")
                KeyButton(key: .right, symbol: "chevron.right", size: pad)
            }
            GridRow {
                Color.clear.frame(width: pad, height: pad)
                KeyButton(key: .down, symbol: "chevron.down", size: pad)
                Color.clear.frame(width: pad, height: pad)
            }
        }
        .padding(6 * scale)
        .background(Circle().fill(.quinary))
    }

    private func rocker(up: RemoteKey, down: RemoteKey, upSymbol: String, downSymbol: String, title: String) -> some View {
        VStack(spacing: 6 * scale) {
            KeyButton(key: up, symbol: upSymbol, size: small)
            Text(title).font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(.secondary)
            KeyButton(key: down, symbol: downSymbol, size: small)
        }
        .padding(.vertical, 6 * scale)
        .padding(.horizontal, 3 * scale)
        .background(Capsule().fill(.quinary))
    }
}
