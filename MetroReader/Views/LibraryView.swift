import SwiftUI
import SwiftData

struct LibraryView: View {
    let onOpen: (Book) -> Void

    @Query(sort: \Book.importedDate, order: .reverse) private var allBooks: [Book]
    @StateObject private var vm = LibraryViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var bookToDelete: Book?
    @State private var showSearch = false
    @State private var showSortSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Metro.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                    if showSearch { searchField }
                    mainContent
                }
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 72)

            bottomNav
        }
        .preferredColorScheme(.dark)
        .onAppear { vm.sanitizeLibrary(books: allBooks, context: modelContext) }
        .fileImporter(
            isPresented: $vm.isImporting,
            allowedContentTypes: [.pdf, .init(filenameExtension: "epub")!],
            allowsMultipleSelection: true
        ) { handleImport($0) }
        .alert("Import Error", isPresented: .constant(vm.importError != nil)) {
            Button("OK") { vm.importError = nil }
        } message: { Text(vm.importError ?? "") }
        .confirmationDialog(
            "Delete \"\(bookToDelete?.title ?? "")\"?",
            isPresented: .constant(bookToDelete != nil),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let b = bookToDelete { vm.deleteBook(b, context: modelContext) }
                bookToDelete = nil
            }
            Button("Cancel", role: .cancel) { bookToDelete = nil }
        }
        .confirmationDialog("Sort By", isPresented: $showSortSheet) {
            ForEach(SortOrder.allCases, id: \.rawValue) { order in
                Button(order.rawValue) { vm.sortOrder = order }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("LIBRARY")
                .font(Metro.displayHero())
                .foregroundStyle(Metro.primary)
                .tracking(-1.5)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showSearch.toggle() }
            } label: {
                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Metro.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Metro.margin)
        .padding(.top, 56)
        .padding(.bottom, 4)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Metro.onSurfaceVariant)
            TextField("", text: $vm.searchText,
                      prompt: Text("Search books…").foregroundStyle(Metro.onSurfaceVariant))
                .foregroundStyle(Metro.onSurface)
                .font(Metro.bodyMd())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Metro.surfaceCont)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Metro.primary).frame(height: 2)
        }
        .padding(.horizontal, Metro.margin)
        .padding(.bottom, Metro.gap)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        let books = vm.filteredBooks(allBooks)

        // Continue Reading featured tile
        if let active = vm.activeBook(from: books) {
            continueTile(active)
        }

        // Category quick-access row
        categoryRow

        // Format filter strip
        formatFilters

        // Book grid or empty state
        if books.isEmpty {
            emptyState
        } else {
            bookGrid(books)
        }
    }

    // MARK: - Continue Reading

    private func continueTile(_ book: Book) -> some View {
        Button { openBook(book) } label: {
            ZStack(alignment: .bottomLeading) {
                tileColor(for: book)

                // Progress fill
                GeometryReader { geo in
                    Rectangle()
                        .fill(Metro.primary)
                        .frame(width: geo.size.width * book.readingPosition, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text("CONTINUE READING")
                        .font(Metro.labelSm())
                        .foregroundStyle(Metro.onSurface.opacity(0.65))
                    Text(book.title.uppercased())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Metro.onSurface)
                        .lineLimit(2)
                }
                .padding(16)
                .padding(.bottom, 6)

                Text("\(Int(book.readingPosition * 100))% READ")
                    .font(Metro.labelSm())
                    .foregroundStyle(Metro.onSurface)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Metro.background.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
            }
            .aspectRatio(2.2, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metro.margin)
        .padding(.bottom, Metro.gap)
        .contextMenu { Button("Delete", role: .destructive) { bookToDelete = book } }
    }

    // MARK: - Category Row

    private var categoryRow: some View {
        HStack(spacing: Metro.gap) {
            categoryTile(
                lines: "RECENT\nIMPORTS", icon: "clock.arrow.circlepath",
                bg: Metro.secondary, fg: Metro.onSecondary, number: "01"
            )
            categoryTile(
                lines: "AUDIO\nBOOKS", icon: "headphones",
                bg: Metro.tertiary, fg: Metro.onTertiary, number: "02"
            )
        }
        .padding(.horizontal, Metro.margin)
        .padding(.bottom, Metro.gap)
    }

    private func categoryTile(
        lines: String, icon: String,
        bg: Color, fg: Color, number: String
    ) -> some View {
        ZStack {
            bg
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(fg)
                    Spacer()
                    Text(number)
                        .font(Metro.labelSm())
                        .foregroundStyle(fg.opacity(0.6))
                }
                Spacer()
                Text(lines)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(fg)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Format Filters

    @State private var selectedFormat: String? = nil

    private var formatFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT FILTERS")
                .font(Metro.labelSm())
                .foregroundStyle(Metro.onSurfaceVariant)
                .padding(.horizontal, Metro.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metro.gap) {
                    filterChip(nil,    label: "ALL")
                    filterChip("epub", label: "EPUB")
                    filterChip("pdf",  label: "PDF")
                }
                .padding(.horizontal, Metro.margin)
            }
        }
        .padding(.bottom, Metro.gap)
    }

    private func filterChip(_ format: String?, label: String) -> some View {
        let active = selectedFormat == format
        return Button {
            selectedFormat = active ? nil : format
        } label: {
            Text(label)
                .font(Metro.labelSm(size: 13))
                .foregroundStyle(active ? Metro.background : Metro.onSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(active ? Metro.primary : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(active ? Metro.primary : Metro.outlineVariant, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Book Grid

    private func bookGrid(_ books: [Book]) -> some View {
        let cols = [GridItem(.flexible(), spacing: Metro.gap),
                    GridItem(.flexible(), spacing: Metro.gap)]
        return LazyVGrid(columns: cols, spacing: Metro.gap) {
            ForEach(books) { book in
                BookTileView(book: book, isHero: false)
                    .onTapGesture { openBook(book) }
                    .contextMenu {
                        Button("Delete", role: .destructive) { bookToDelete = book }
                    }
            }
        }
        .padding(.horizontal, Metro.margin)
        .padding(.bottom, 24)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Metro.gap) {
            Text("NO BOOKS YET")
                .font(Metro.headlineLg())
                .foregroundStyle(Metro.onSurfaceVariant)
            Text("Import a PDF or EPUB to get started")
                .font(Metro.bodyMd())
                .foregroundStyle(Metro.onSurfaceVariant.opacity(0.6))
            Button { vm.isImporting = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("IMPORT")
                        .font(Metro.labelSm(size: 14))
                }
                .foregroundStyle(Metro.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Metro.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, Metro.margin)
    }

    // MARK: - Bottom Nav

    private var bottomNav: some View {
        HStack(spacing: 28) {
            navButton(icon: "plus", filled: false)  { vm.isImporting = true }
            navButton(icon: "magnifyingglass", filled: true) {
                withAnimation(.easeInOut(duration: 0.18)) { showSearch.toggle() }
            }
            navButton(icon: "arrow.up.arrow.down", filled: false) { showSortSheet = true }
            navButton(icon: "ellipsis", filled: false) {}
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Metro.surfaceContLow)
        .overlay(alignment: .top) {
            Rectangle().fill(Metro.surfaceContHighest).frame(height: 2)
        }
    }

    private func navButton(icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(filled ? Metro.onPrimary : Metro.onSurface)
                .frame(width: filled ? 54 : 46, height: filled ? 54 : 46)
                .background(filled ? Metro.primary : Color.clear)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(filled ? Color.clear : Metro.onSurface, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func tileColor(for book: Book) -> Color {
        let palette: [Color] = [
            Metro.primaryContainer,
            Color(metroHex: "#1e4d2b"),
            Color(metroHex: "#5c1a1a"),
            Color(metroHex: "#3a1445"),
            Color(metroHex: "#4d2800"),
            Metro.surfaceContHigh,
        ]
        return palette[abs(book.title.hashValue) % palette.count]
    }

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
