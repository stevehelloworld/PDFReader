import SwiftUI

// MARK: - Page scrubber

struct PageScrubber: View {
    @Binding var currentPage: Int
    let totalPages: Int
    var onSeek: (Int) -> Void
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var maxContentWidth: CGFloat { horizontalSizeClass == .regular ? 640 : .infinity }
    #else
    private let maxContentWidth: CGFloat = .infinity
    #endif

    var body: some View {
        if totalPages > 1 {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(currentPage) },
                        set: { onSeek(Int($0.rounded())) }
                    ),
                    in: 1...Double(totalPages),
                    step: 1
                )
                .controlSize(.small)

                Text(String(localized: "第 \(currentPage) / \(totalPages) 頁"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

// MARK: - Appearance filter overlay for inverted / sepia pages

struct AppearanceFilterOverlay: View {
    let appearance: ReadingAppearance

    var body: some View {
        switch appearance {
        case .inverted:
            Color.white
                .blendMode(.difference)
                .opacity(1)
                .allowsHitTesting(false)
        case .sepia:
            Color(red: 0.95, green: 0.88, blue: 0.7)
                .blendMode(.multiply)
                .opacity(0.25)
                .allowsHitTesting(false)
        case .night:
            Color.blue
                .blendMode(.multiply)
                .opacity(0.08)
                .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}

// MARK: - Loading overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            // Background dimming only; the progress card stays inside the safe area.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .transition(.opacity)
        .allowsHitTesting(true)
    }
}
