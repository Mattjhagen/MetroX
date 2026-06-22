import SwiftUI
import SwiftData

struct LibraryView: View {
    let onOpen: (Book) -> Void

    @Query(sort: \Book.importedDate, order: .reverse) private var allBooks: [Book]
    @StateObject private var vm = LibraryViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var bookToDelete: Book?

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: Hero tile — Continue Reading
                        if let active = vm.activeBook(from: vm.filteredBooks(allBooks)) {
                            sectionHeader("Continue Reading")

                            BookTileView(book: active, isHero: true)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 16)
                                .onTapGesture { openBook(active) }
                                .contextMenu { deleteMenu(active) }
                        }

                        // MARK: Library grid
                        sectionHeader("Library")

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(vm.filteredBooks(allBooks)) { book in
                                BookTileView(book: book, isHero: false)
                                    .onTapGesture { openBook(book) }
                                    .contextMenu { deleteMenu(book) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 32)

                        if allBooks.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("MetroReader")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $vm.searchText, prompt: "Search books")
            .onAppear { vm.sanitizeLibrary(books: allBooks, context: modelContext) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    importButton
                }
            }
            .fileImporter(
                isPresented: $vm.isImporting,
                allowedContentTypes: [.pdf, .init(filenameExtension: "epub")!],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .alert("Import Error", isPresented: .constant(vm.importError != nil)) {
                Button("OK") { vm.importError = nil }
            } message: {
                Text(vm.importError ?? "")
            }
            .confirmationDialog("Delete \"\(bookToDelete?.title ?? "")\"?",
                                isPresented: .constant(bookToDelete != nil),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let b = bookToDelete { vm.deleteBook(b, context: modelContext) }
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) { bookToDelete = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .tracking(1.5)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func deleteMenu(_ book: Book) -> some View {
        Button("Delete", role: .destructive) {
            bookToDelete = book
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No books yet")
                .foregroundStyle(.white.opacity(0.5))
            Button("Import a book") { vm.isImporting = true }
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.rawValue) { order in
                Button {
                    vm.sortOrder = order
                } label: {
                    if vm.sortOrder == order {
                        Label(order.rawValue, systemImage: "checkmark")
                    } else {
                        Text(order.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.white)
        }
    }

    private var importButton: some View {
        Button {
            vm.isImporting = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(.white)
        }
    }

    // MARK: - Actions

    private func openBook(_ book: Book) {
        book.lastOpenedDate = Date()
        try? modelContext.save()
        onOpen(book)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            vm.importError = err.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    try vm.importBook(url: url, context: modelContext, existingBooks: allBooks)
                } catch {
                    vm.importError = error.localizedDescription
                }
            }
        }
    }
}
