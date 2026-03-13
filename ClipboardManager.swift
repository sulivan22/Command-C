//
//  ClipboardManager.swift
//  Porta papeles
//
//  Created by Sulivan Antonety on 18/11/25.
//
import Foundation
import AppKit

enum ClipKind: String, Codable {
    case text
    case image
    case code
    case url
    case file
    case unknown
}

struct ClipItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let kind: ClipKind
    let text: String?
    let imagePath: String?
    let sourceAppName: String?
    let sourceBundleID: String?
    var pinned: Bool
    var category: String   // ← NUEVO: categoría asignada

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: ClipKind,
        text: String? = nil,
        imagePath: String? = nil,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        pinned: Bool = false,
        category: String = "General"
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.pinned = pinned
        self.category = category
    }

    var imageURL: URL? {
        guard let imagePath else { return nil }
        return URL(fileURLWithPath: imagePath)
    }

    var thumbnailNSImage: NSImage? {
        guard let url = imageURL else { return nil }
        return NSImage(contentsOf: url)
    }
}

class ClipboardManager: ObservableObject {
    private static let itemsKey = "ClipboardItemsV4" // ← Incremento versión de storage
    private static let maxItems = Int.max

    @Published var items: [ClipItem] = [] {
        didSet { save() }
    }

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        createClipsFolderIfNeeded()
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "ClipboardApp"
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(bundleID, isDirectory: true)
    }

    private func clipsFolderURL() -> URL {
        appSupportURL().appendingPathComponent("Clips", isDirectory: true)
    }

    private func createClipsFolderIfNeeded() {
        let fm = FileManager.default
        let url = clipsFolderURL()
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey) {
            if var decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {

                // Asignar categoría "General" si faltaba en versiones antiguas
                for i in decoded.indices {
                    if decoded[i].category.isEmpty {
                        decoded[i].category = "General"
                    }
                }

                self.items = decoded
                return
            }
        }
        self.items = []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceName = sourceApp?.localizedName
        let bundleID = sourceApp?.bundleIdentifier

        // FILE
        if let itemsPB = pb.pasteboardItems {
            for item in itemsPB {
                if let fileURLString = item.string(forType: .fileURL),
                   let url = URL(string: fileURLString)
                {
                    let path = url.path

                    let newItem = ClipItem(
                        kind: .file,
                        text: path,
                        imagePath: nil,
                        sourceAppName: sourceName,
                        sourceBundleID: bundleID,
                        pinned: false,
                        category: "General"
                    )

                    if !isDuplicate(newItem) {
                        appendItem(newItem)
                    }
                    return
                }
            }
        }

        // STRICT IMAGE CHECK (fix Word/Excel bug)
        if let types = pb.types, types.contains(.tiff) || types.contains(.png) {

            if let image = NSImage(pasteboard: pb),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:])
            {
                let id = UUID()
                let fileURL = clipsFolderURL().appendingPathComponent("\(id.uuidString).png")

                if (try? png.write(to: fileURL, options: .atomic)) != nil {
                    let newItem = ClipItem(
                        id: id,
                        kind: .image,
                        text: nil,
                        imagePath: fileURL.path,
                        sourceAppName: sourceName,
                        sourceBundleID: bundleID,
                        pinned: false,
                        category: "General"
                    )
                    if !isDuplicate(newItem) { appendItem(newItem) }
                }
                return
            }
        }

        // TEXT
        if let copied = pb.string(forType: .string) {
            let normalized = copied
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalized.isEmpty else { return }

            let kind: ClipKind

            // URL detection
            if let url = URL(string: normalized), url.scheme != nil || normalized.contains(".") {
                kind = .url
            }
            // Code detection
            else if isLikelyCode(normalized) {
                kind = .code
            }
            else {
                kind = .text
            }

            let newItem = ClipItem(
                kind: kind,
                text: normalized,
                imagePath: nil,
                sourceAppName: sourceName,
                sourceBundleID: bundleID,
                pinned: false,
                category: "General"
            )

            if !isDuplicate(newItem) { appendItem(newItem) }
            return
        }
    }

    private func appendItem(_ item: ClipItem) {
        DispatchQueue.main.async {
            self.items.append(item)
            self.resort()
            self.trimIfNeeded()
        }
    }

    private func isDuplicate(_ item: ClipItem) -> Bool {
        guard let last = items.first else { return false }
        if last.kind != item.kind { return false }
        switch item.kind {
        case .text, .code, .url, .file:
            return last.text == item.text
        case .image:
            return last.imagePath == item.imagePath
        default:
            return false
        }
    }

    deinit { timer?.invalidate() }

    func clear() { self.items.removeAll() }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .image:
            if let url = item.imageURL,
               let img = NSImage(contentsOf: url)
            { pb.writeObjects([img]) }

        case .file:
            if let path = item.text {
                let url = URL(fileURLWithPath: path)
                pb.writeObjects([url as NSURL])
            }

        default:
            if let t = item.text {
                pb.setString(t, forType: .string)
            }
        }
    }

    func togglePin(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].pinned.toggle()
            resort()
        }
    }

    func delete(_ item: ClipItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            if let path = items[idx].imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            items.remove(at: idx)
        }
    }

    private func resort() {
        items.sort { a, b in
            if a.pinned != b.pinned {
                return a.pinned && !b.pinned
            }
            return a.date > b.date
        }
    }

    private func trimIfNeeded() {
        if items.count > Self.maxItems {
            let overflow = items.suffix(from: Self.maxItems)
            for item in overflow {
                if let path = item.imagePath { try? FileManager.default.removeItem(atPath: path) }
            }
            items = Array(items.prefix(Self.maxItems))
        }
    }

    // MARK: - CATEGORY SYSTEM

    /// Asignar categoría a un ítem.
    func assignCategory(_ category: String, to itemID: UUID) {
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            items[idx].category = category
        }
    }

    /// Obtener lista de categorías usadas por items
    func usedCategories() -> [String] {
        let set = Set(items.map { $0.category })
        return Array(set).sorted()
    }

    /// Filtrar items por categoría
    func items(in category: String) -> [ClipItem] {
        items.filter { $0.category == category }
    }
}

private func isLikelyCode(_ text: String) -> Bool {
    let indicators = ["{", "}", "func ", "class ", "let ", ";", "var ", "=>", "import ", "#include", "public ", "private "]
    let score = indicators.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
    return score >= 3
}
