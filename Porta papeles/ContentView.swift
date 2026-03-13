import SwiftUI
import WebKit
import ServiceManagement

@MainActor
struct ContentView: View {
    @StateObject private var manager = ClipboardManager()
    @State private var search = ""
    @State private var selected: ClipItem?
    @State private var lastSelectedID: ClipItem.ID? = nil
    @State private var refreshKey = UUID()
    @State private var showClearConfirm = false
    @State private var recentlyDeleted: Set<ClipItem.ID> = []

    // UI State
    @State private var showSettings = false
    @State private var showCategories = false

    // Settings toggles (basic wiring; system integration can be added later)
    @State private var launchAtLogin = false

    // Categories model (simple in-memory for now)
    @State private var categories: [String] = ["General"]
    @State private var selectedCategoryIndex: Int = 0
    @State private var newCategoryName: String = ""
    @State private var showAddCategoryField = false
    @State private var settingsError: String? = nil

    @State private var showFirstRun: Bool = false

    var body: some View {
        NavigationStack {
            MainContentView(
                manager: manager,
                search: $search,
                selected: $selected,
                lastSelectedID: $lastSelectedID,
                refreshKey: $refreshKey,
                showClearConfirm: $showClearConfirm,
                recentlyDeleted: $recentlyDeleted,
                showSettings: $showSettings,
                showCategories: $showCategories,
                launchAtLogin: $launchAtLogin,
                categories: $categories,
                selectedCategoryIndex: $selectedCategoryIndex,
                settingsError: $settingsError,
                showFirstRun: $showFirstRun
            )
        }
    }
}

private struct MainContentView: View {
    @ObservedObject var manager: ClipboardManager
    @Binding var search: String
    @Binding var selected: ClipItem?
    @Binding var lastSelectedID: ClipItem.ID?
    @Binding var refreshKey: UUID
    @Binding var showClearConfirm: Bool
    @Binding var recentlyDeleted: Set<ClipItem.ID>

    @Binding var showSettings: Bool
    @Binding var showCategories: Bool

    @Binding var launchAtLogin: Bool

    @Binding var categories: [String]
    @Binding var selectedCategoryIndex: Int
    @Binding var settingsError: String?

    @Binding var showFirstRun: Bool

    // For assigning categories
    @State private var showCategoryPickerFor: ClipItem.ID? = nil
    @State private var showNoCategoriesAlert: Bool = false

    @State private var filterKind: ClipKind? = nil
    @State private var isListView: Bool = false


    // Helper binding to simplify type-checking for the settings error alert
    private var isSettingsErrorPresented: Binding<Bool> {
        Binding<Bool>(
            get: { settingsError != nil },
            set: { newValue in if !newValue { settingsError = nil } }
        )
    }

    private var filteredItems: [ClipItem] {
        if search.isEmpty { return manager.items }
        return manager.items.filter { ($0.text ?? "").lowercased().contains(search.lowercased()) }
    }

    private var filteredByKind: [ClipItem] {
        let base = filteredItems

        // Filter by kind if selected
        let byKind: [ClipItem]
        if let kind = filterKind {
            byKind = base.filter { $0.kind == kind }
        } else {
            byKind = base
        }

        // Filter by category if not "General"
        if selectedCategoryIndex > 0 {
            let category = categories[selectedCategoryIndex]
            return byKind.filter { $0.category == category }
        } else {
            return byKind
        }
    }

    private var baseView: some View {
        VStack(spacing: 12) {
            header
            filterBar.padding(.horizontal)
            cardsScroller
            Spacer(minLength: 0)
            bottomBar
        }
    }

    var body: some View {
        baseView
        .alert("Borrar todo el portapapeles?", isPresented: $showClearConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) { manager.clear() }
        } message: {
            Text("Esta acción eliminará todo el historial.")
        }
        .alert("Error de Ajustes", isPresented: isSettingsErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingsError ?? "")
        }
        .alert("No hay categorías", isPresented: $showNoCategoriesAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Crea una categoría antes de asignar.")
        }
        .id(refreshKey)
        .frame(minWidth: 660, idealWidth: 864, maxWidth: 1092, minHeight: 351, idealHeight: 388, maxHeight: 517)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .preferredColorScheme(nil)
        .modifier(NavigationDestinationCompatClip(selected: $selected))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PopoverWillClose"))) { _ in
            handlePopoverWillClose()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PopoverWillShow"))) { _ in
            handlePopoverWillShow()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CardPinToggle"))) { note in
            handleCardPinToggle(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CardDelete"))) { note in
            handleCardDelete(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenDetailFromCard"))) { note in
            handleOpenDetailFromCard(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CopyFromContext"))) { note in
            handleCopyFromContext(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AssignCategory"))) { note in
            if let itemID = note.object as? UUID {
                if categories.count > 0 {
                    showCategoryPickerFor = itemID
                    showCategories = true
                } else {
                    showNoCategoriesAlert = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CategoryAssigned"))) { note in
            guard
                let userInfo = note.userInfo,
                let itemID = userInfo["itemID"] as? UUID,
                let category = userInfo["category"] as? String
            else { return }
            manager.assignCategory(category, to: itemID)
            refreshKey = UUID()
            showCategories = false
        }
        .onChange(of: launchAtLogin) { newValue in
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    settingsError = error.localizedDescription
                    print("LoginItem error: \(error)")
                }
            } else {
                print("LoginItem requires macOS 13+")
            }
        }
        .overlay {
            if showSettings {
                OverlayPanel(onDismiss: { showSettings = false }) {
                    SettingsSheet(
                        launchAtLogin: $launchAtLogin,
                        onQuit: { NSApp.terminate(nil) }
                    )
                    .frame(width: 360)
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(20)
            }
        }
        .overlay {
            if showCategories {
                OverlayPanel(onDismiss: {
                    showCategories = false
                    showCategoryPickerFor = nil
                }) {
                    CategoriesSheet(
                        categories: $categories,
                        selectedIndex: $selectedCategoryIndex,
                        selectedItemForCategory: $showCategoryPickerFor
                    )
                    .frame(width: 300, height: 300)
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(30)
            }
        }
        .alert("Recomendación", isPresented: $showFirstRun) {
            Button("Cancelar", role: .cancel) {}
            Button("Habilitar") {
                launchAtLogin = true
                if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
                showFirstRun = false
            }
        } message: {
            Text("Habilita Command-C para que abra automáticamente al iniciar sesión.")
        }
        .onAppear {
            if #available(macOS 13.0, *) {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                showFirstRun = !launchAtLogin
            } else {
                showFirstRun = false
            }
            #if DEBUG
            if manager.items.isEmpty {
                let sample = ClipItem(kind: .text, text: "Ejemplo de portapapeles", imagePath: nil, sourceAppName: "Debug", pinned: false)
                manager.items.append(sample)
            }
            #endif
            // Load categories from UserDefaults (persisted)
            if let saved = UserDefaults.standard.array(forKey: "SavedCategories") as? [String], !saved.isEmpty {
                categories = saved
            } else {
                categories = ["General"]
            }
        }
        .onChange(of: categories) { newValue in
            // Remove duplicates, ensure "General" is first
            var filtered = Array(NSOrderedSet(array: newValue)) as! [String]
            if let idx = filtered.firstIndex(where: { $0.caseInsensitiveCompare("General") == .orderedSame }) {
                filtered.remove(at: idx)
            }
            filtered.insert("General", at: 0)
            categories = filtered
            UserDefaults.standard.set(filtered, forKey: "SavedCategories")
        }
    }

    private func handlePopoverWillClose() {
        lastSelectedID = selected?.id
    }

    private func handlePopoverWillShow() {
        if let id = lastSelectedID, let item = manager.items.first(where: { $0.id == id }) {
            selected = item
        }
        refreshKey = UUID()
    }

    private func handleCardPinToggle(_ note: Notification) {
        if let id = note.object as? ClipItem.ID,
           let item = manager.items.first(where: { $0.id == id }) {
            manager.togglePin(item)
        }
    }

    private func handleCardDelete(_ note: Notification) {
        if let id = note.object as? ClipItem.ID, let item = manager.items.first(where: { $0.id == id }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                manager.delete(item)
                recentlyDeleted.insert(item.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    recentlyDeleted.remove(item.id)
                }
            }
        }
    }

    private func handleOpenDetailFromCard(_ note: Notification) {
        if let id = note.object as? ClipItem.ID, let item = manager.items.first(where: { $0.id == id }) {
            selected = item
        }
    }

    private func handleCopyFromContext(_ note: Notification) {
        if let id = note.object as? ClipItem.ID, let item = manager.items.first(where: { $0.id == id }) {
            manager.copy(item)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text("Historial")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer(minLength: 8)

            SearchPill(text: $search)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)

            Button(action: { isListView.toggle() }) {
                Image(systemName: isListView ? "square.grid.2x2" : "list.bullet")
                    .foregroundColor(.primary)
            }
            .help("Cambiar vista")

            Button(action: { showClearConfirm = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .help("Borrar historial")
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var bottomBar: some View {
        ZStack {
            // Centered icons
            HStack(spacing: 32) {
                CircleIcon("list.bullet", color: .orange)
                    .onTapGesture { showCategories = true }
                    .help("Categorías")

                CircleIcon("gearshape", color: .purple)
                    .onTapGesture { showSettings = true }
                    .help("Ajustes")
            }
            .frame(maxWidth: .infinity)

            // Counter aligned to the right
            HStack {
                Spacer()
                counterView
                    .padding(.trailing, 14)
            }
        }
        .padding(.bottom, 16)
    }

    private var counterView: some View {
        Text("\(manager.items.count) ítems")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(.trailing, 14)
    }

    @ViewBuilder
    private var cardsScroller: some View {
        if filteredByKind.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No hay elementos del portapapeles aún")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 8)
        } else {
            if isListView {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredByKind) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.kindSystemImage)
                                    .foregroundColor(item.kindColor)
                                if item.kind == .image {
                                    Text("Imagen")
                                        .font(.subheadline)
                                } else {
                                    Text(item.text?.components(separatedBy: "\n").first ?? "")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let bundleID = item.sourceBundleID,
                                   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                                    Image(nsImage: icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { selected = item }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                HorizontalScrollContainer {
                    CardsRow(items: filteredByKind, recentlyDeleted: $recentlyDeleted, onSelect: { item in selected = item })
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            filterPill(title: "All", kind: nil)
            filterPill(title: "Text", kind: .text)
            filterPill(title: "Code", kind: .code)
            filterPill(title: "Image", kind: .image)
            filterPill(title: "Link", kind: .url)
            filterPill(title: "File", kind: .file)
            filterCategoryPill
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func systemImage(for kind: ClipKind?) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        default: return "circle"
        }
    }
    private func color(for kind: ClipKind?) -> Color {
        switch kind {
        case .text: return .blue
        case .code: return .purple
        case .image: return .pink
        case .url: return .green
        case .file: return .orange
        default: return .gray
        }
    }

    private func filterPill(title: String, kind: ClipKind?) -> some View {
        let pillColor: Color = {
            if kind == nil { return Color.teal }
            return color(for: kind)
        }()
        
        let isActive = (filterKind == kind)

        return Button(action: {
            filterKind = kind
            if kind == nil { selectedCategoryIndex = 0 }
        }) {
            HStack(spacing: 6) {
                Image(systemName: systemImage(for: kind))
                    .foregroundColor(pillColor)
                    .font(.system(size: 10))
                
                Text(title)
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(pillColor)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(pillColor.opacity(isActive ? 0.20 : 0.10))
            )
            .overlay(
                Capsule()
                    .stroke(pillColor.opacity(isActive ? 1.0 : 0.25), lineWidth: isActive ? 1.2 : 0.6)
            )
            .foregroundColor(pillColor)
        }
        .buttonStyle(.plain)
    }

    private var filterCategoryPill: some View {
        let isActive = (selectedCategoryIndex > 0)

        return Menu {
            if categories.count <= 1 {
                Button("No hay categorías creadas") {}.disabled(true)
            } else {
                ForEach(categories.indices.filter { $0 != 0 }, id: \.self) { idx in
                    Button(categories[idx]) {
                        selectedCategoryIndex = idx
                        filterKind = nil
                        refreshKey = UUID()
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundColor(.mint)
                    .font(.system(size: 10))

                Text("Categoría")
                    .foregroundColor(.mint)

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.mint)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.mint.opacity(isActive ? 0.20 : 0.10))
            )
            .overlay(
                Capsule()
                    .stroke(Color.mint.opacity(isActive ? 1.0 : 0.25), lineWidth: isActive ? 1.2 : 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OverlayPanel<Content: View>: View {
    let onDismiss: () -> Void
    let content: Content

    init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            content
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 12)
        }
    }
}

private func isCodeLike(_ s: String) -> Bool {
    let lowered = s.lowercased()
    if s.contains("\n") { return true }
    let tokens = ["{", "}", ";", "func ", "class ", "struct ", "switch ", "case ", "let ", "var ", "if ", "else "]
    return tokens.contains { lowered.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
}

private struct ClipCard: View {
    let item: ClipItem
    @Binding var recentlyDeleted: Set<ClipItem.ID>
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTick = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.kindSystemImage)
                    .foregroundColor(item.kindColor)
                    .padding(4)
                    .background(item.kindColor.opacity(0.15))
                    .font(.system(size: 11))     // icono más pequeño
                    .clipShape(Capsule())
                if item.pinned {
                    Image(systemName: "pin.fill").foregroundStyle(.yellow).help("Fijado")
                }
                Spacer()
                // Show originating app icon, if available
                if let bundleID = item.sourceBundleID,
                   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help(item.sourceAppName ?? bundleID)
                }
            }

            preview

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button { // Copy
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    switch item.kind {
                    case .image:
                        if let img = item.thumbnailNSImage { pb.writeObjects([img]) }
                    case .file:
                        if let path = item.text { pb.writeObjects([URL(fileURLWithPath: path)] as [NSURL]) }
                    default:
                        if let t = item.text { pb.setString(t, forType: .string) }
                    }
                } label: { CircleIcon("doc.on.doc", color: .blue) }
                .buttonStyle(.plain)

                Button { // Open
                    NotificationCenter.default.post(name: Notification.Name("OpenDetailFromCard"), object: item.id)
                } label: { CircleIcon("eye", color: .green) }
                .buttonStyle(.plain)

                Button { // Pin
                    NotificationCenter.default.post(name: Notification.Name("CardPinToggle"), object: item.id)
                } label: { CircleIcon(item.pinned ? "pin.fill" : "pin", color: .orange) }
                .buttonStyle(.plain)

                Button(role: .destructive) { // Delete
                    showTick = true
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        NotificationCenter.default.post(name: Notification.Name("CardDelete"), object: item.id)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showTick = false
                    }
                } label: { CircleIcon("trash", color: .red) }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 6)
        }
        .scaleEffect(showTick ? 0.97 : 1)
        .opacity(showTick ? 0.9 : 1)
        .padding(12)
        .frame(width: 200, height: 170)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(color: (colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.3)), radius: (colorScheme == .light ? 6 : 10), x: 0, y: (colorScheme == .light ? 2 : 4))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            ZStack {
                if showTick {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .transition(.opacity)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.green)
                        .scaleEffect(showTick ? 1.0 : 0.6)
                        .opacity(showTick ? 1.0 : 0.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showTick)
                }
            }
        )
    }

    private var footerInfo: String { "" }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let img = item.thumbnailNSImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                placeholder("Sin vista previa")
            }
        case .code:
            Text(item.text ?? "")
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(6)
        case .text:
            if let t = item.text {
                if isCodeLike(t) {
                    Text(t)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(6)
                } else {
                    Text(t)
                        .font(.subheadline)
                        .lineLimit(4)
                }
            } else {
                Text("")
                    .font(.subheadline)
                    .lineLimit(4)
            }
        case .url:
            WebThumbnailView(urlString: item.text)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .file:
            HStack(spacing: 10) {
                Image(systemName: "doc")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text((item.text as NSString?)?.lastPathComponent ?? (item.text ?? "Archivo"))
                        .font(.subheadline)
                        .lineLimit(1)
                    Text((item.text as NSString?)?.deletingLastPathComponent ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        default:
            Text("Elemento no soportado")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func placeholder(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }.frame(height: 110)
    }
}

private struct CircleIcon: View {
    let systemName: String
    let color: Color
    init(_ systemName: String, color: Color) { self.systemName = systemName; self.color = color }
    var body: some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.2), in: Circle())
    }
}

private extension ClipItem {
    var kindTitle: String {
        switch kind {
        case .text: return "Text"
        case .code: return "Code"
        case .image: return "Image"
        case .url: return "Link"
        case .file: return "File"
        default: return "Item"
        }
    }
    var kindSystemImage: String {
        switch kind {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        default: return "questionmark.circle"
        }
    }
    var kindColor: Color {
        switch kind {
        case .text: return .blue
        case .code: return .purple
        case .image: return .pink
        case .url: return .green
        case .file: return .orange
        default: return .gray
        }
    }
}

private struct DetailItemView: View {
    let item: ClipItem
    var onClose: (() -> Void)? = nil
    @State private var appearKey = UUID()

    var body: some View {
        ZStack {
            // Dimmed background to allow clicking outside to close
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onClose?() }

            VStack(alignment: .leading, spacing: 12) {

                // Top bar with integrated action buttons and app icon
                HStack {
                    // Close button
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Centered action buttons
                    HStack(spacing: 20) {
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            switch item.kind {
                            case .image:
                                if let img = item.thumbnailNSImage { pb.writeObjects([img]) }
                            case .file:
                                if let path = item.text { pb.writeObjects([URL(fileURLWithPath: path)] as [NSURL]) }
                            default:
                                if let t = item.text { pb.setString(t, forType: .string) }
                            }
                        } label: {
                            CircleIcon("doc.on.doc", color: .blue)
                        }
                        .buttonStyle(.plain)

                        if item.kind == .url, let s = item.text, let url = URL(string: s) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                CircleIcon("safari", color: .green)
                            }
                            .buttonStyle(.plain)
                        }

                        if item.kind == .file, let path = item.text {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            } label: {
                                CircleIcon("folder", color: .orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // App icon
                    if let bundleID = item.sourceBundleID,
                       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // MAIN CONTENT
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        switch item.kind {
                        case .image:
                            if let img = item.thumbnailNSImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal)
                            }
                        case .text, .unknown:
                            Text(item.text ?? "")
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(.horizontal)
                        case .code:
                            Text(item.text ?? "")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.horizontal)
                        case .file:
                            VStack(alignment: .leading, spacing: 6) {
                                Text((item.text as NSString?)?.lastPathComponent ?? "Archivo")
                                    .font(.title3).bold()
                                Text(item.text ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal)
                        case .url:
                            if let s = item.text, let url = URL(string: s) {
                                VStack(alignment: .leading, spacing: 10) {
                                    WebThumbnailView(urlString: s)
                                        .frame(height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .padding(.horizontal)
                                    Text(url.absoluteString)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 18)
                }

            }
            .frame(width: 430, height: 500)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipped()
            .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 12)
        }
        .edgesIgnoringSafeArea(.all)
    }
}

private struct NavigationDestinationCompatClip: ViewModifier {
    @Binding var selected: ClipItem?
    private var isPresented: Binding<Bool> {
        Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
    }

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .navigationDestination(isPresented: isPresented) {
                    if let item = selected {
                        DetailItemView(item: item, onClose: { selected = nil })
                            .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button(action: { selected = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                }
                            }
                    }
                }
        } else {
            content
        }
    }
}

private struct HorizontalScrollContainer<Content: View>: NSViewRepresentable {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HorizontalWheelScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false // oculto
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        let hosting = NSHostingView(rootView: AnyView(HStack { content() }))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        // Constraints to let content size drive scrollable area
        hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hosting = nsView.documentView as? NSHostingView<AnyView> {
            hosting.rootView = AnyView(HStack { content() })
        }
    }
}

private final class HorizontalWheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Compute effective horizontal delta
        let dx: CGFloat
        if abs(event.scrollingDeltaX) > 0.1 {
            dx = -event.scrollingDeltaX
        } else {
            // Map vertical wheel to horizontal; amplify for non-precise wheels
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            dx = -event.scrollingDeltaY * factor
        }

        if let doc = documentView {
            var origin = contentView.bounds.origin
            let maxX = max(0, doc.bounds.width - contentView.bounds.width)
            origin.x = min(maxX, max(0, origin.x + dx))
            contentView.setBoundsOrigin(origin)
            reflectScrolledClipView(contentView)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private struct WebThumbnailView: View {
    let urlString: String?
    @State private var favicon: NSImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon = favicon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }

            Text(cleanURL)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        )
        .frame(height: 40)
        .onAppear { loadFavicon() }
    }

    private var cleanURL: String {
        guard let s = urlString, let u = URL(string: s) else { return urlString ?? "" }
        return (u.host ?? s)
    }

    private func loadFavicon() {
        guard let s = urlString, let url = URL(string: s), let host = url.host else { return }
        let faviconURL = URL(string: "https://" + host + "/favicon.ico")!
        URLSession.shared.dataTask(with: faviconURL) { data, _, _ in
            if let data = data, let img = NSImage(data: data) {
                DispatchQueue.main.async { self.favicon = img }
            }
        }.resume()
    }
}

private struct SettingsSheet: View {
    @Binding var launchAtLogin: Bool
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajustes")
                .font(.headline)
                .padding(.top, 8)

            Toggle("Abrir al inicio", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)

            HStack {
                Spacer()
                Button(action: { onQuit() }) {
                    CircleIcon("power", color: .red)
                }
                .buttonStyle(.plain)
                .help("Salir")
            }

            Text("Los cambios de integración del sistema se aplicarán cuando configuremos los permisos correspondientes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding()
    }
}

private struct CategoriesSheet: View {
    @Binding var categories: [String]
    @Binding var selectedIndex: Int
    @Binding var selectedItemForCategory: UUID?
    @State private var newCategoryName: String = ""
    @State private var showAddField: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack {
                Text("Categorías")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { showAddField.toggle() }
                } label: {
                    Image(systemName: showAddField ? "xmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Add category field
            if showAddField {
                HStack(spacing: 8) {
                    TextField("Nombre de la categoría", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                    Button("Agregar") {
                        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        if !categories.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                            categories.append(name)
                            newCategoryName = ""
                            withAnimation { showAddField = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 4)
            }

            // Category list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(categories.indices, id: \.self) { idx in
                        HStack {
                            Text(categories[idx])
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            if idx == 0 {
                                Text("Fija")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if selectedItemForCategory != nil && idx != 0 {
                                Button {
                                    if let itemID = selectedItemForCategory {
                                        NotificationCenter.default.post(
                                            name: Notification.Name("CategoryAssigned"),
                                            object: nil,
                                            userInfo: ["itemID": itemID, "category": categories[idx]]
                                        )
                                        selectedItemForCategory = nil
                                    }
                                } label: {
                                    Image(systemName: "arrow.turn.down.right")
                                        .foregroundStyle(.mint)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                            }

                            if idx != 0 && selectedItemForCategory == nil {
                                Button {
                                    categories.remove(at: idx)
                                    if selectedIndex >= categories.count {
                                        selectedIndex = max(0, categories.count - 1)
                                    }
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(idx == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedIndex = idx }
                    }
                }
                .padding(.vertical, 6)
            }

            Text("La categoría 'General' no se puede borrar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

        }
        .padding(16)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 12)
        .padding()
    }
}

private struct FirstRunSheet: View {
    var enableAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recomendación")
                .font(.headline)
            Text("Inicia automáticamente Command-C cuando reinicies tu Mac.")
                .font(.body)
            HStack {
                Spacer()
                Button(role: .none, action: { enableAction() }) {
                    Text("Habilitar")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding()
    }
}

private struct SearchPill: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar…", text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06)))
    }
}

private struct CardsRow: View {
    let items: [ClipItem]
    @Binding var recentlyDeleted: Set<ClipItem.ID>
    var onSelect: (ClipItem) -> Void

    var body: some View {
        LazyHStack(spacing: 10) {
            ForEach(items) { item in
                ClipCard(item: item, recentlyDeleted: $recentlyDeleted)
                    .contextMenu {
                        Button("Copiar") {
                            NotificationCenter.default.post(name: Notification.Name("CopyFromContext"), object: item.id)
                        }
                        Button(item.pinned ? "Desfijar" : "Fijar") {
                            NotificationCenter.default.post(name: Notification.Name("CardPinToggle"), object: item.id)
                        }
                        Button("Asignar categoría") {
                            NotificationCenter.default.post(name: Notification.Name("AssignCategory"), object: item.id)
                        }
                        Divider()
                        Button(role: .destructive) {
                            NotificationCenter.default.post(name: Notification.Name("CardDelete"), object: item.id)
                        } label: { Text("Eliminar") }
                    }
                    .onTapGesture { onSelect(item) }
            }
        }
    }
}
