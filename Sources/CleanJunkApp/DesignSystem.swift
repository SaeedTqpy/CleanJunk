import CleanJunkCore
import SwiftUI

enum CJStyle {
    static let mint = Color(red: 0.25, green: 0.80, blue: 0.69)
    static let violet = Color(red: 0.62, green: 0.55, blue: 0.98)
    static let amber = Color(red: 0.98, green: 0.69, blue: 0.34)
    static let subtle = Color.primary.opacity(0.06)

    static func color(for category: ArtifactCategory) -> Color {
        switch category {
        case .xcode: return mint
        case .packageCache: return violet
        case .appCache: return Color.blue
        case .developerLogs: return amber
        case .workspace: return Color.cyan
        case .docker: return Color.gray
        }
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CJStyle.subtle, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05), lineWidth: 1)
            }
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }
}

struct Pill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let footnote: String
    let symbol: String
    let tint: Color

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.subheadline.weight(.medium))
                    Text(footnote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

extension Int64 {
    var cjSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension RiskLevel {
    var cjColor: Color {
        switch self {
        case .reconstructible: return CJStyle.mint
        case .review: return CJStyle.amber
        case .protected: return .secondary
        }
    }
}
