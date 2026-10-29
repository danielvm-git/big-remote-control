import SwiftUI

/// Round remote-style button.
struct PadButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                Circle()
                    .fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
            .overlay { Circle().strokeBorder(.separator, lineWidth: 0.5) }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Capsule button for rows (volume, channel, apps).
struct PillButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height * 0.42, weight: .medium))
            .padding(.horizontal, height * 0.45)
            .frame(minHeight: height)
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .background { Capsule().fill(.quaternary) }
            .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

struct KeyButton: View {
    @Environment(AppModel.self) private var model
    let key: RemoteKey
    let symbol: String
    var size: CGFloat = 36
    var prominent = false

    var body: some View {
        Button { model.press(key) } label: { Image(systemName: symbol) }
            .buttonStyle(PadButtonStyle(size: size, prominent: prominent))
            .help(key.label)
            .accessibilityLabel(key.label)
    }
}

struct StatusDot: View {
    let power: PowerState

    var color: Color {
        switch power {
        case .unknown: return .gray
        case .off: return .red
        case .standby: return .orange
        case .on, .tv: return .green
        case .art: return .purple
        }
    }

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity)
    }
}
