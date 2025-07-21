import SwiftUI
import CoreNFC

struct Tag: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    let nfcData: String
    let timestamp: Date

    init(id: UUID = UUID(), name: String, nfcData: String, timestamp: Date) {
        self.id = id
        self.name = name
        self.nfcData = nfcData
        self.timestamp = timestamp
    }
}

class NFCScanner: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    @Published var tags: [Tag] = [] {
        didSet { saveTags() }
    }
    @Published var scanError: String?

    private var session: NFCNDEFReaderSession?
    private let tagsKey = "NFCPassTags"

    override init() {
        super.init()
        loadTags()
    }

    func startScan() {
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            self.scanError = error.localizedDescription
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let payloads = messages.flatMap { $0.records }
        let data = payloads.map { record in
            if record.typeNameFormat == .nfcWellKnown,
               let type = String(data: record.type, encoding: .utf8),
               type == "T",
               record.payload.count > 3 {
                let statusByte = record.payload[0]
                let langCodeLen = Int(statusByte & 0x3F)
                let textData = record.payload.subdata(in: (1 + langCodeLen)..<record.payload.count)
                return String(data: textData, encoding: .utf8) ?? "Unreadable tag"
            } else {
                return record.payload.map { String(format: "%02x", $0) }.joined()
            }
        }.joined(separator: "\n")
        DispatchQueue.main.async {
            let tag = Tag(name: "Untitled", nfcData: data, timestamp: Date())
            self.tags.append(tag)
        }
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsKey)
        }
    }

    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: tagsKey),
           let savedTags = try? JSONDecoder().decode([Tag].self, from: data) {
            tags = savedTags
        }
    }
}

struct ContentView: View {
    @StateObject private var scanner = NFCScanner()
    @State private var selectedTag: Tag?
    @State private var isEditing = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if scanner.tags.isEmpty {
                    VStack {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Tags Scanned...")
                            .foregroundColor(.secondary)
                            .font(.headline)
                            .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.top, 32)
                    Spacer()
                } else {
                    List {
                        ForEach(scanner.tags) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(tag.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(tag.nfcData)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    HStack {
                                        Text(tag.timestamp, style: .date)
                                        Text(tag.timestamp, style: .time)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                        }
                        .onDelete { indexSet in
                            scanner.tags.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
                Spacer()
                Button(action: { scanner.startScan() }) {
                    Label("Scan NFC", systemImage: "wave.3.right")
                        .font(.title2.bold())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("NFC Pass")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(item: $selectedTag) { tag in
                TagDetailSheet(tag: tag, scanner: scanner, selectedTag: $selectedTag)
            }
            .alert("NFC Error", isPresented: .constant(scanner.scanError != nil), actions: {
                Button("OK") { scanner.scanError = nil }
            }, message: {
                Text(scanner.scanError ?? "")
            })
        }
    }
}

struct TagDetailSheet: View {
    @State var tag: Tag
    @ObservedObject var scanner: NFCScanner
    @Binding var selectedTag: Tag?
    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 120)
                    .cornerRadius(20, corners: [.topLeft, .topRight])
                VStack {
                    Image(systemName: "tag")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                    Text("NFC Tag")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Tag Name")
                        .font(.headline)
                    Spacer()
                }
                TextField("Enter name", text: $tag.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("Tag Data")
                    .font(.headline)
                ScrollView {
                    Text(tag.nfcData)
                        .font(.body)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                Button(action: {
                    UIPasteboard.general.string = tag.nfcData
                    showCopied = true
                }) {
                    Label("Copy Tag Data", systemImage: "doc.on.doc")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .alert(isPresented: $showCopied) {
                    Alert(title: Text("Copied!"), message: Text("Tag data copied to clipboard."), dismissButton: .default(Text("OK")))
                }
                Text("Timestamp")
                    .font(.headline)
                HStack {
                    Text(tag.timestamp, style: .date)
                    Text(tag.timestamp, style: .time)
                }
                .font(.body)
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .onDisappear {
            if let idx = scanner.tags.firstIndex(where: { $0.id == tag.id }) {
                scanner.tags[idx].name = tag.name
            }
        }
    }
}

// Helper for rounded corners on specific edges
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
