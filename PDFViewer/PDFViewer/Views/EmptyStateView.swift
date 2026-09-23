import SwiftUI

struct EmptyStateView: View {
    @ObservedObject var historyManager: PDFHistoryManager
    let isLoading: Bool
    let onOpen: () -> Void
    let onOpenRecent: (RecentFile) -> Void
    let onRemoveRecent: (RecentFile) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 16) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text(String(localized: "請開啟一個 PDF 檔案"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(String(localized: "支援單頁、雙頁與右至左閱讀，並自動記住進度。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                Button(action: onOpen) {
                    Label(String(localized: "開啟檔案"), systemImage: "doc.badge.plus")
                        .font(.headline)
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)
                .accessibilityLabel(String(localized: "開啟檔案"))

                #if os(macOS)
                Text(String(localized: "或將 PDF 拖曳到此視窗 · ⌘O"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                #endif
            }
            .padding(.horizontal, 24)

            if isLoading {
                ProgressView(String(localized: "正在載入…"))
                    .padding(.top, 24)
            }

            if !historyManager.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "最近開啟"))
                            .font(.headline)
                        Spacer()
                        Button(String(localized: "清除"), role: .destructive, action: onClearRecents)
                            .font(.caption)
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(historyManager.recentFiles) { file in
                                RecentFileRow(file: file) {
                                    onOpenRecent(file)
                                } onDelete: {
                                    onRemoveRecent(file)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
                .frame(maxWidth: 480)
                .padding(.top, 36)
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecentFileRow: View {
    let file: RecentFile
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var thumbnail: PlatformImage?
    @ObservedObject private var history = PDFHistoryManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                thumbnailView
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(String(localized: "第 \(file.currentPage) 頁"))
                        Text("·")
                        Text(formatDate(file.lastOpened))
                        if file.totalPages > 0 {
                            Text("·")
                            Text("\(Int(file.progressFraction * 100))%")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if file.totalPages > 0 {
                        ProgressView(value: file.progressFraction)
                            .progressViewStyle(.linear)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onDelete {
                Button(String(localized: "從列表移除"), role: .destructive, action: onDelete)
            }
        }
        .task(id: file.id) {
            thumbnail = await history.generateThumbnail(for: file)
        }
        .accessibilityLabel(Text("\(file.name), \(String(localized: "第 \(file.currentPage) 頁"))"))
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            #if os(macOS)
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #else
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #endif
        } else {
            ZStack {
                Color.secondary.opacity(0.12)
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return String(localized: "今天") + " " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return String(localized: "昨天")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}
