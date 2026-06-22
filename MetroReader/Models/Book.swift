import Foundation
import SwiftData
import SwiftUI

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var fileURL: URL
    var readingPosition: Double   // 0.0–1.0
    var lastOpenedDate: Date?
    var importedDate: Date

    init(id: UUID = UUID(), title: String, fileURL: URL) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.readingPosition = 0
        self.lastOpenedDate = nil
        self.importedDate = Date()
    }

    var isCompleted: Bool { readingPosition > 0.95 }

    var format: BookFormat {
        switch fileURL.pathExtension.lowercased() {
        case "epub": return .epub
        default:     return .pdf
        }
    }
}

enum BookFormat {
    case pdf, epub
}

enum SortOrder: String, CaseIterable {
    case recent  = "Recent"
    case oldest  = "Oldest"
    case unread  = "Unread First"
}
