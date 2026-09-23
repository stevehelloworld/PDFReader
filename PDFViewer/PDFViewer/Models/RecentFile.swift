import Foundation

struct RecentFile: Codable, Identifiable, Equatable {
    /// Stable identity: prefer bookmark data; path matching handles refreshed bookmarks.
    let id: String
    let path: String
    let name: String
    let lastOpened: Date
    var currentPage: Int
    var totalPages: Int
    var readingMode: String
    var isContinuous: Bool
    var appearance: String
    var zoomLevel: String
    /// Security-scoped bookmark for durable re-open (iOS/macOS sandbox).
    var bookmarkData: Data?

    init(
        path: String,
        name: String,
        currentPage: Int = 1,
        totalPages: Int = 0,
        readingMode: ReadingMode = .singlePage,
        isContinuous: Bool = false,
        appearance: ReadingAppearance = .automatic,
        zoomLevel: ZoomLevel = .fitPage,
        bookmarkData: Data? = nil,
        id: String? = nil
    ) {
        self.id = id ?? Self.makeID(name: name, path: path, bookmarkData: bookmarkData)
        self.path = path
        self.name = name
        self.lastOpened = Date()
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.readingMode = readingMode.rawValue
        self.isContinuous = isContinuous
        self.appearance = appearance.rawValue
        self.zoomLevel = zoomLevel.rawValue
        self.bookmarkData = bookmarkData
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, name, lastOpened, currentPage, totalPages
        case readingMode, isContinuous, appearance, zoomLevel, bookmarkData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        lastOpened = try c.decodeIfPresent(Date.self, forKey: .lastOpened) ?? Date()
        currentPage = try c.decodeIfPresent(Int.self, forKey: .currentPage) ?? 1
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        readingMode = try c.decodeIfPresent(String.self, forKey: .readingMode) ?? ReadingMode.singlePage.rawValue
        isContinuous = try c.decodeIfPresent(Bool.self, forKey: .isContinuous) ?? false
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? ReadingAppearance.automatic.rawValue
        zoomLevel = try c.decodeIfPresent(String.self, forKey: .zoomLevel) ?? ZoomLevel.fitPage.rawValue
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
        if let decodedID = try c.decodeIfPresent(String.self, forKey: .id) {
            id = decodedID
        } else {
            id = Self.makeID(name: name, path: path, bookmarkData: bookmarkData)
        }
    }

    static func makeID(name: String, path: String, bookmarkData: Data?) -> String {
        if let bookmarkData {
            return "bm-\(bookmarkData.prefix(32).base64EncodedString())"
        }
        return "\(path)|\(name)"
    }

    var progressFraction: Double {
        guard totalPages > 0 else { return 0 }
        return min(1, max(0, Double(currentPage) / Double(totalPages)))
    }
}
