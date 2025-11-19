//
//  AppDelegate.swift
//  Porta papeles
//
//  Created by Sulivan Antonety on 18/11/25.
//

import SwiftUI
import AppKit

@objcMembers
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            button.action = #selector(togglePopover)
        }

        popover.contentSize = NSSize(width: 350, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
