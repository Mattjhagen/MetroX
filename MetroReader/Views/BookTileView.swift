import SwiftUI

struct BookTileView: View {
    let book: Book
    let isHero: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background block — Metro flat style
            tileColor
                .overlay(alignment: .bottomLeading) {
                    if book.readingPosition > 0 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: geo.size.width * book.readingPosition)
                                .frame(maxHeight: 3, alignment: .bottom)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(book.title)
                    .font(.system(size: isHero ? 20 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(isHero ? 3 : 2)
                    .padding([.horizontal, .bottom], isHero ? 16 : 10)
            }

            if book.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .opacity(tileOpacity)
        .aspectRatio(isHero ? 2.5 : 1.4, contentMode: .fit)
        .clipped()
    }

    private var tileColor: Color {
        // Deterministic color from title hash
        let colors: [Color] = [
            Color(red: 0.00, green: 0.48, blue: 0.75),  // metro blue
            Color(red: 0.40, green: 0.60, blue: 0.25),  // metro green
            Color(red: 0.75, green: 0.22, blue: 0.17),  // metro red
            Color(red: 0.50, green: 0.18, blue: 0.56),  // metro purple
            Color(red: 0.90, green: 0.49, blue: 0.13),  // metro orange
            Color(red: 0.13, green: 0.59, blue: 0.65),  // metro teal
        ]
        let hash = abs(book.title.hashValue) % colors.count
        return colors[hash]
    }

    private var tileOpacity: Double {
        if book.isCompleted { return 0.45 }
        if book.readingPosition > 0 { return 0.80 }
        return 1.0
    }
}
