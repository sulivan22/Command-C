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
            button.image = NSImage(systemSymbolName: "c.square", accessibilityDescription: nil)
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 350, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            let event = NSApp.currentEvent
            if event?.type == .rightMouseUp {
                let menu = NSMenu()
                let restartItem = NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "")
                restartItem.target = self
                menu.addItem(restartItem)
                menu.addItem(NSMenuItem(title: "Exit", action: #selector(quitApp), keyEquivalent: "q"))
                statusItem.menu = menu
                statusItem.button?.performClick(nil)
                statusItem.menu = nil
                return
            }
            if popover.isShown {
                popover.performClose(nil)
            } else {
                NotificationCenter.default.post(name: Notification.Name("PopoverWillShow"), object: nil)
                popover.contentSize = NSSize(width: 620, height: 430)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    if let window = self.popover.contentViewController?.view.window {
                        var frame = window.frame
                        frame.origin.x -= 80
                        window.setFrame(frame, display: true)
                    }
                }
            }
        }
    }

    @objc func restartApp() {
        popover.performClose(nil)
        let path = Bundle.main.bundlePath
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [path]
            try? task.run()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func applyMenuBarOnlyPolicy() {
        let enabled = UserDefaults.standard.bool(forKey: "menuBarOnly")
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)

            if enabled {
                NSApp.hide(nil)
            } else {
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func updateMenuBarOnly(_ note: Notification) {
        applyMenuBarOnlyPolicy()
    }
}
