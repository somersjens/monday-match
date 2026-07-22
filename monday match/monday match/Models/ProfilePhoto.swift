import Foundation

struct ProfilePhoto: Identifiable, Codable, Equatable {
    let id: UUID
    var imageData: Data
    var order: Int

    init(
        id: UUID = UUID(),
        imageData: Data,
        order: Int
    ) {
        self.id = id
        self.imageData = imageData
        self.order = order
    }
}
