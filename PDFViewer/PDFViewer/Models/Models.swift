import Foundation
import SwiftUI

// MARK: - Reading Mode

enum ReadingMode: String, CaseIterable, Identifiable, Codable {
    case singlePage = "singlePage"
    case twoPagesLTR = "twoPagesLTR"
    case twoPagesRTL = "twoPagesRTL"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .singlePage: return String(localized: "單頁")
        case .twoPagesLTR: return String(localized: "雙頁左至右")
        case .twoPagesRTL: return String(localized: "雙頁右至左")
        }
    }

    var icon: String {
        switch self {
        case .singlePage: return "doc.text"
        case .twoPagesLTR: return "book"
        case .twoPagesRTL: return "book.closed"
        }
    }

    var description: String {
        switch self {
        case .singlePage: return String(localized: "單頁模式")
        case .twoPagesLTR: return String(localized: "雙頁模式（左至右）")
        case .twoPagesRTL: return String(localized: "雙頁模式（右至左）")
        }
    }

    var isBookMode: Bool {
        self != .singlePage
    }

    var isRTL: Bool {
        self == .twoPagesRTL
    }
}

// MARK: - Zoom Level

enum ZoomLevel: String, CaseIterable, Identifiable {
    case fitPage
    case fitWidth
    case percent50
    case percent75
    case percent100
    case percent125
    case percent150
    case percent200

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fitPage: return String(localized: "適應頁面")
        case .fitWidth: return String(localized: "適應寬度")
        case .percent50: return "50%"
        case .percent75: return "75%"
        case .percent100: return "100%"
        case .percent125: return "125%"
        case .percent150: return "150%"
        case .percent200: return "200%"
        }
    }

    var scaleFactor: CGFloat? {
        switch self {
        case .fitPage, .fitWidth: return nil
        case .percent50: return 0.5
        case .percent75: return 0.75
        case .percent100: return 1.0
        case .percent125: return 1.25
        case .percent150: return 1.5
        case .percent200: return 2.0
        }
    }

    static var percentageLevels: [ZoomLevel] {
        allCases.filter { $0.scaleFactor != nil }
    }
}

// MARK: - Reading Appearance (night / sepia)

enum ReadingAppearance: String, CaseIterable, Identifiable {
    case automatic
    case light
    case sepia
    case night
    case inverted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return String(localized: "自動")
        case .light: return String(localized: "淺色")
        case .sepia: return String(localized: "護眼")
        case .night: return String(localized: "夜間")
        case .inverted: return String(localized: "反色")
        }
    }

    var icon: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .sepia: return "eyeglasses"
        case .night: return "moon.fill"
        case .inverted: return "circle.bottomhalf.filled"
        }
    }
}

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails
    case outline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thumbnails: return String(localized: "縮圖")
        case .outline: return String(localized: "目錄")
        }
    }

    var icon: String {
        switch self {
        case .thumbnails: return "rectangle.grid.1x2"
        case .outline: return "list.bullet"
        }
    }
}

// MARK: - PDF Errors

enum PDFError: LocalizedError {
    case fileNotFound
    case invalidPDF
    case cannotRead
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return String(localized: "找不到 PDF 檔案")
        case .invalidPDF: return String(localized: "無效的 PDF 檔案或檔案已損壞")
        case .cannotRead: return String(localized: "無法讀取 PDF 檔案，請檢查檔案權限")
        case .accessDenied: return String(localized: "無法存取此檔案，請重新選擇")
        }
    }
}
