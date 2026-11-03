import SwiftUI

#if os(iOS)
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recent
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return String(localized: "最近開啟")
        case .name: return String(localized: "名稱")
        }
    }
}

/// iOS library column (NavigationSplitView sidebar). Compact width shows this as the
/// root of the collapsed stack, keeping the P0 open-a-book flow.
struct LibraryView: View {
    @ObservedObject var historyManager: PDFHistoryManager
    let selectedFileID: String?
    let isLoading: Bool
    let sortOrder: LibrarySortOrder
    let onOpen: () -> Void
    let onOpenRecent: (RecentFile) -> Void
    let onRemoveRecent: (RecentFile) -> Void
    let onClearRecents: () -> Void

    private var sortedFiles: [RecentFile] {
        switch sortOrder {
        case .recent:
            return historyManager.recentFiles.sorted { $0.lastOpened > $1.lastOpened }
        case .name:
            return historyManager.recentFiles.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        if historyManager.recentFiles.isEmpty {
            EmptyStateView(
                historyManager: historyManager,
                isLoading: isLoading,
                onOpen: onOpen,
                onOpenRecent: onOpenRecent,
                onRemoveRecent: onRemoveRecent,
                onClearRecents: onClearRecents
            )
        } else {
            List {
                Section {
                    ForEach(sortedFiles) { file in
                        RecentFileRow(file: file) {
                            onOpenRecent(file)
                        } onDelete: {
                            onRemoveRecent(file)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(
                            file.id == selectedFileID
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .accessibilityAddTraits(file.id == selectedFileID ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text(String(localized: "最近開啟"))
                        Spacer()
                        Button(String(localized: "清除"), role: .destructive, action: onClearRecents)
                            .font(.caption)
                    }
                }
                if isLoading {
                    ProgressView(String(localized: "正在載入…"))
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.sidebar)
        }
    }
}
#endif
