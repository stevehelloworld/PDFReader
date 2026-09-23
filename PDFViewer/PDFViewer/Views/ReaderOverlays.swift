import SwiftUI

// MARK: - Edge tap zones (prev / next page)

struct EdgeTapOverlay: View {
    let isRTL: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    var edgeFraction: CGFloat = 0.12

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width * edgeFraction, 44)

            HStack(spacing: 0) {
                edgeButton(
                    systemName: isRTL ? "chevron.right" : "chevron.left",
                    accessibility: isRTL ? String(localized: "下一頁") : String(localized: "上一頁")
                ) {
                    if isRTL { onNext() } else { onPrevious() }
                }
                .frame(width: width)

                Color.clear
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)

                edgeButton(
                    systemName: isRTL ? "chevron.left" : "chevron.right",
                    accessibility: isRTL ? String(localized: "上一頁") : String(localized: "下一頁")
                ) {
                    if isRTL { onPrevious() } else { onNext() }
                }
                .frame(width: width)
            }
        }
        // Only edge buttons intercept touches; center stays free for PDF gestures.
        .allowsHitTesting(true)
    }

    private func edgeButton(systemName: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Color.clear
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

// MARK: - Page scrubber

struct PageScrubber: View {
    @Binding var currentPage: Int
    let totalPages: Int
    var onSeek: (Int) -> Void

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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
