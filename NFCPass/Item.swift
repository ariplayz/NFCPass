import Foundation
import SwiftData

@Model
class Item: Identifiable {
    var id: UUID
    var timestamp: Date
    var nfcData: String?

    init(timestamp: Date, nfcData: String?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.nfcData = nfcData
    }
}
