import Foundation
import SwiftData

@Model
class Item {
    var timestamp: Date
    var nfcData: String?

    init(timestamp: Date, nfcData: String? = nil) {
        self.timestamp = timestamp
        self.nfcData = nfcData
    }
}
