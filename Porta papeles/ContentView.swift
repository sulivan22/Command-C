import SwiftUI

struct ContentView: View {
    @StateObject private var manager = ClipboardManager()
    @State private var search = ""

    var body: some View {
        VStack(spacing: 12) {
            
            HStack {
                Text("Historial")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: { manager.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .help("Borrar historial")
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Search bar
            TextField("Buscar…", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredItems.indices, id: \.self) { index in
                        ClipItemCard(text: filteredItems[index])
                    }
                }
                .animation(.default, value: filteredItems)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 350, height: 450)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
    
    private var filteredItems: [String] {
        if search.isEmpty { return manager.items }
        return manager.items.filter { $0.lowercased().contains(search.lowercased()) }
    }
}
