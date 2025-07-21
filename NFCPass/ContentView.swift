import SwiftUI
import SwiftData
import CoreNFC

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var scanError: String?
    @State private var selectedTag: String?

    var body: some View {
        NavigationSplitView {
            VStack {
                Spacer()
                Button(action: startNFCScan) {
                    Label("Scan NFC", systemImage: "wave.3.right")
                        .font(.title)
                        .padding()
                }
                Spacer()
                List {
                    ForEach(items) { item in
                        Button {
                            selectedTag = item.nfcData ?? "No data"
                        } label: {
                            Text(item.nfcData ?? "No data")
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        } detail: {
            Text("Select an item")
        }
        .alert("NFC Error", isPresented: .constant(scanError != nil), actions: {
            Button("OK") { scanError = nil }
        }, message: {
            Text(scanError ?? "")
        })
        .alert("Tag Data", isPresented: .constant(selectedTag != nil), actions: {
            Button("OK") { selectedTag = nil }
        }, message: {
            Text(selectedTag ?? "")
        })
    }

    private func startNFCScan() {
        let session = NFCNDEFReaderSession(delegate: NFCDelegate { message, error in
            if let error = error {
                scanError = error.localizedDescription
            } else if let message = message {
                withAnimation {
                    let newItem = Item(timestamp: Date(), nfcData: message)
                    modelContext.insert(newItem)
                }
            }
        }, queue: nil, invalidateAfterFirstRead: true)
        session.begin()
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

class NFCDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    let completion: (String?, Error?) -> Void

    init(completion: @escaping (String?, Error?) -> Void) {
        self.completion = completion
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        completion(nil, error)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let payloads = messages.flatMap { $0.records }
        let data = payloads.compactMap { String(data: $0.payload, encoding: .utf8) }.joined(separator: "\n")
        completion(data, nil)
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // No action needed, just silences the warning
    }
}
