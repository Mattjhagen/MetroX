import SwiftUI
import SwiftData

@main
struct MetroReaderApp: App {
    @AppStorage("activeBookID") private var activeBookIDString: String = ""
    @State private var autoOpenAttempted = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Book.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(sharedModelContainer)
        }
    }
}

struct RootView: View {
    @Query(sort: \Book.lastOpenedDate, order: .reverse) private var books: [Book]
    @State private var activeBook: Book?
    @AppStorage("activeBookID") private var activeBookIDString: String = ""
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let book = activeBook {
                ReaderContainerView(book: book) {
                    activeBook = nil
                    activeBookIDString = ""
                }
            } else {
                LibraryView(onOpen: { book in
                    activeBook = book
                    activeBookIDString = book.id.uuidString
                })
            }
        }
        .onAppear { attemptAutoResume() }
    }

    private func attemptAutoResume() {
        guard !activeBookIDString.isEmpty,
              let uuid = UUID(uuidString: activeBookIDString),
              let book = books.first(where: { $0.id == uuid })
        else {
            activeBookIDString = ""
            return
        }

        guard BookValidation.isResumeEligible(book) else {
            RecoveryLogger.log(.autoResumeBlocked(
                bookID: book.id,
                reason: BookValidation.isReadable(book) ? "not resume-eligible" : "file missing"
            ))
            activeBookIDString = ""
            return
        }

        activeBook = book
    }
}
