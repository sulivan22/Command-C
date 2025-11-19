//
//  ClipboardManager.swift
//  Porta papeles
//
//  Created by Sulivan Antonety on 18/11/25.
//

import Foundation
import AppKit

class ClipboardManager: ObservableObject {
    private static let itemsKey = "ClipboardItems"
    @Published var items: [String] = [] {
        didSet {
            UserDefaults.standard.set(items, forKey: Self.itemsKey)
        }
    }
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.itemsKey) {
            self.items = saved
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkClipboard()
        }
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general

        if pb.changeCount != lastChangeCount {
            lastChangeCount = pb.changeCount

            if let copied = pb.string(forType: .string),
               !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               (items.last != copied) {

                DispatchQueue.main.async {
                    self.items.insert(copied, at: 0)
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
    
    func clear() {
        self.items.removeAll()
    }
}
