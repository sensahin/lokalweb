import Foundation

struct DatabaseSnapshot: Identifiable, Hashable {
    var id: String { fileURL.path }
    let fileURL: URL
    let createdAt: Date
    let byteCount: Int64

    var displayName: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
