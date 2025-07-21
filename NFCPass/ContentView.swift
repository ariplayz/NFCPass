import SwiftUI
import CoreNFC

// MARK: - Tag Model with Type
enum TagType: String, Codable, CaseIterable, Identifiable {
    case text = "Text"
    case uri = "URI"
    case mime = "MIME"

    var id: String { rawValue }
}

struct Tag: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var nfcData: String
    var type: TagType
    let timestamp: Date

    init(id: UUID = UUID(), name: String, nfcData: String, type: TagType = .text, timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.nfcData = nfcData
        self.type = type
        self.timestamp = timestamp
    }
}

// MARK: - NFC Manager
class NFCScanner: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
    @Published var tags: [Tag] = [] {
        didSet { saveTags() }
    }
    @Published var scanError: String?

    private let tagsKey = "NFCPassTags"

    private var readSession: NFCNDEFReaderSession?
    private var writeSession: NFCNDEFReaderSession?

    private var tagToWrite: Tag?

    override init() {
        super.init()
        loadTags()
    }

    func startReadSession() {
        tagToWrite = nil
        readSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        readSession?.alertMessage = "Hold your iPhone near an NFC tag to read."
        readSession?.begin()
    }

    func startWriteSession(with tag: Tag) {
        tagToWrite = tag
        writeSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        writeSession?.alertMessage = "Hold your iPhone near an NFC tag to write."
        writeSession?.begin()
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        print("NFC Session did become active")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code == .readerSessionInvalidationErrorUserCanceled ||
                readerError.code == .readerSessionInvalidationErrorSessionTimeout {
                return
            }
        }
        DispatchQueue.main.async {
            self.scanError = error.localizedDescription
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard session == readSession else { return }
        guard let message = messages.first else {
            session.alertMessage = "No NDEF found."
            session.invalidate()
            return
        }

        let payloads = message.records
        let data = payloads.map { self.parseRecord($0) }.joined(separator: "\n")

        DispatchQueue.main.async {
            let newTag = Tag(name: "New Tag", nfcData: data)
            self.tags.append(newTag)
        }

        session.alertMessage = "NFC tag read successfully!"
        session.invalidate()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if session == writeSession {
            handleWrite(tags: tags, session: session)
        } else if session == readSession {
            guard let tag = tags.first else {
                session.alertMessage = "No tag found."
                session.invalidate()
                return
            }
            session.connect(to: tag) { [weak self] error in
                if let error = error {
                    session.alertMessage = "Connection failed: \(error.localizedDescription)"
                    session.invalidate()
                    return
                }

                tag.queryNDEFStatus { status, _, error in
                    if let error = error {
                        session.alertMessage = "Status failed: \(error.localizedDescription)"
                        session.invalidate()
                        return
                    }

                    if status == .notSupported {
                        session.alertMessage = "Tag not supported."
                        session.invalidate()
                        return
                    }

                    tag.readNDEF { message, error in
                        if let error = error {
                            session.alertMessage = "Read failed: \(error.localizedDescription)"
                        } else if let message = message {
                            let payloads = message.records
                            let data = payloads.map { self?.parseRecord($0) ?? "" }.joined(separator: "\n")

                            DispatchQueue.main.async {
                                let newTag = Tag(name: "New Tag", nfcData: data)
                                self?.tags.append(newTag)
                            }

                            session.alertMessage = "NFC tag read successfully!"
                        } else {
                            session.alertMessage = "No NDEF message found."
                        }
                        session.invalidate()
                    }
                }
            }
        }
    }

    private func handleWrite(tags: [NFCNDEFTag], session: NFCNDEFReaderSession) {
        guard let nfcTag = tags.first, let tagToWrite = tagToWrite else {
            session.alertMessage = "No tag or data to write."
            session.invalidate()
            return
        }

        session.connect(to: nfcTag) { [weak self] error in
            if let error = error {
                session.alertMessage = "Connection failed: \(error.localizedDescription)"
                session.invalidate()
                return
            }

            let payload: NFCNDEFPayload
            switch tagToWrite.type {
            case .text:
                payload = NFCNDEFPayload(format: .nfcWellKnown,
                                         type: "T".data(using: .utf8)!,
                                         identifier: Data(),
                                         payload: tagToWrite.nfcData.data(using: .utf8)!)
            case .uri:
                let uriPayload = Data([0x00]) + (tagToWrite.nfcData.data(using: .utf8) ?? Data())
                payload = NFCNDEFPayload(format: .nfcWellKnown,
                                         type: "U".data(using: .utf8)!,
                                         identifier: Data(),
                                         payload: uriPayload)
            case .mime:
                payload = NFCNDEFPayload(format: .media,
                                         type: "text/plain".data(using: .utf8)!,
                                         identifier: Data(),
                                         payload: tagToWrite.nfcData.data(using: .utf8)!)
            }

            let message = NFCNDEFMessage(records: [payload])

            nfcTag.writeNDEF(message) { error in
                if let error = error {
                    session.alertMessage = "Write failed: \(error.localizedDescription)"
                } else {
                    session.alertMessage = "Write successful!"
                }
                session.invalidate()
                self?.tagToWrite = nil
            }
        }
    }

    func parseRecord(_ record: NFCNDEFPayload) -> String {
        switch record.typeNameFormat {
        case .nfcWellKnown:
            if let type = String(data: record.type, encoding: .utf8) {
                if type == "T" {
                    let statusByte = record.payload[0]
                    let langCodeLen = Int(statusByte & 0x3F)
                    let textData = record.payload.subdata(in: (1 + langCodeLen)..<record.payload.count)
                    return "[Text] " + (String(data: textData, encoding: .utf8) ?? "Unreadable Text")
                } else if type == "U" {
                    let uriPayload = record.payload
                    guard uriPayload.count >= 1 else { return "Invalid URI" }
                    let uriBody = uriPayload.subdata(in: 1..<uriPayload.count)
                    let uri = String(data: uriBody, encoding: .utf8) ?? ""
                    return "[URI] \(uri)"
                } else {
                    return "[Well-Known: \(type)] " + record.payload.map { String(format: "%02x", $0) }.joined()
                }
            }
            return "[Well-Known: Unknown type] " + record.payload.map { String(format: "%02x", $0) }.joined()

        case .media:
            return "[MIME: \(String(data: record.type, encoding: .utf8) ?? "unknown")] " + record.payload.map { String(format: "%02x", $0) }.joined()

        case .absoluteURI:
            return "[Absolute URI] " + (String(data: record.payload, encoding: .utf8) ?? record.payload.map { String(format: "%02x", $0) }.joined())

        case .nfcExternal:
            return "[External] " + record.payload.map { String(format: "%02x", $0) }.joined()

        default:
            return "[Unknown] " + record.payload.map { String(format: "%02x", $0) }.joined()
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

// MARK: - Main View
struct ContentView: View {
    @StateObject private var scanner = NFCScanner()
    @State private var selectedTag: Tag?
    @State private var showCreateSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if scanner.tags.isEmpty {
                    VStack {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No Tags...")
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
                                    Text("[\(tag.type.rawValue)] \(tag.nfcData)")
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

                HStack(spacing: 12) {
                    Button(action: { showCreateSheet = true }) {
                        Label("Add Tag", systemImage: "plus")
                            .font(.title3.bold())
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: { scanner.startReadSession() }) {
                        Label("Scan NFC", systemImage: "wave.3.right")
                            .font(.title3.bold())
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
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
            .sheet(isPresented: $showCreateSheet) {
                CreateTagSheet(scanner: scanner, isPresented: $showCreateSheet)
            }
            .alert("NFC Error", isPresented: .constant(scanner.scanError != nil), actions: {
                Button("OK") { scanner.scanError = nil }
            }, message: {
                Text(scanner.scanError ?? "")
            })
        }
    }
}

// MARK: - Tag Detail
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
                TextField("Tag Name", text: $tag.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Picker("Type", selection: $tag.type) {
                    ForEach(TagType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                TextField("Tag Data", text: $tag.nfcData)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: {
                    UIPasteboard.general.string = tag.nfcData
                    showCopied = true
                }) {
                    Label("Copy Tag Data", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .alert(isPresented: $showCopied) {
                    Alert(title: Text("Copied!"), message: Text("Tag data copied to clipboard."), dismissButton: .default(Text("OK")))
                }

                Button(action: {
                    scanner.startWriteSession(with: tag)
                }) {
                    Label("Write Tag", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .onDisappear {
            if let idx = scanner.tags.firstIndex(where: { $0.id == tag.id }) {
                scanner.tags[idx] = tag
            }
        }
    }
}

// MARK: - Create Tag Sheet
struct CreateTagSheet: View {
    @ObservedObject var scanner: NFCScanner
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var data = ""
    @State private var type: TagType = .text

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tag Details")) {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(TagType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    TextField("Data", text: $data)
                }
                Section {
                    Button("Save") {
                        let newTag = Tag(name: name.isEmpty ? "New Tag" : name, nfcData: data, type: type)
                        scanner.tags.append(newTag)
                        isPresented = false
                    }
                    .disabled(data.isEmpty)
                }
            }
            .navigationTitle("New Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Helper
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
