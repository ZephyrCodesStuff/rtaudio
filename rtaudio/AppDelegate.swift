//
//  AppDelegate.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//


import Cocoa

// TODO: use this?
func getAppleMusicArtwork() -> NSImage? {
    let script = """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        end try
    end tell
    """
    
    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let output = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("🍎 AppleScript Blocked/Failed: \(error)")
            return nil
        }
        
        print(output.data)
        return NSImage(data: output.data)
    }
    
    return nil
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel!
    let audioScanner = SystemAudioScanner()
    var metalView: WaveformMTKView!

    let width: CGFloat = 135
    let height: CGFloat = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create the native Metal View directly
        metalView = WaveformMTKView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            audio: audioScanner
        )
        
        // 2. Setup the invisible floating panel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 3. Inject the Metal view straight into the WindowServer, no SwiftUI needed
        panel.contentView = metalView
        panel.delegate = self
        
        // Position at top-right, above the menu bar
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelX = visibleFrame.maxX - width
        let panelY = visibleFrame.maxY - height
        panel.setFrame(NSRect(x: panelX, y: panelY, width: width, height: height), display: true)
        
        panel.makeKeyAndOrderFront(nil)
        
        // 🚀 4. AUTO-START THE AUDIO CAPTURE
        Task {
            await audioScanner.startCapture()
        }
    }

    // 5. Hardware-accelerated pause when hidden
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if window.occlusionState.contains(.visible) {
            audioScanner.isPaused = false
            metalView.isVisualizerPaused = false
        } else {
            audioScanner.isPaused = true
            metalView.isVisualizerPaused = true
        }
    }
}
