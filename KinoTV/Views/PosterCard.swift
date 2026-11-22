import SwiftUI

struct PosterCard: View {
    let item: MetaItem
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.2))
                AsyncImage(url: URL(string: item.poster)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(item.name)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}
