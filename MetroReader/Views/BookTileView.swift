import SwiftUI

struct BookTileView: View {
    let book: Book
    let isHero: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            tileColor

            // Bottom progress fill bar
            if book.readingPosition > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Metro.primary)
                        .frame(width: geo.size.width * book.readingPosition, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }

            // Format badge — top-right
            Text(formatBadge)
                .font(Metro.labelSm(size: 10))
                .foregroundStyle(badgeColor.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Metro.background.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)

            // Completion checkmark — top-left
            if book.isCompleted {
                Text("DONE")
                    .font(Metro.labelSm(size: 9))
                    .foregroundStyle(Metro.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
            }

            // Title — bottom-left
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title.uppercased())
                    .font(Metro.tileTitle(size: isHero ? 18 : 14))
                    .foregroundStyle(Metro.onSurface)
                    .lineLimit(isHero ? 3 : 2)
            }
            .padding(isHero ? 14 : 10)
            .padding(.bottom, 4)
        }
        .opacity(tileOpacity)
        .aspectRatio(isHero ? 2.2 : 1.1, contentMode: .fit)
        .clipped()
    }

    private var tileColor: Color {
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

    private var formatBadge: String {
        book.fileURL.pathExtension.uppercased()
    }

    private var badgeColor: Color {
        switch book.fileURL.pathExtension.lowercased() {
        case "epub": return Metro.secondary
        case "pdf":  return Metro.primary
        default:     return Metro.tertiary
        }
    }

    private var tileOpacity: Double {
        if book.isCompleted    { return 0.45 }
        if book.readingPosition > 0 { return 0.85 }
        return 1.0
    }
}
