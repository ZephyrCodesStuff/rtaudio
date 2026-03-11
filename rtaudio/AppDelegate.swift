//
//  AppDelegate.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import AVFAudio
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
        metalView = WaveformMTKView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            audio: audioScanner
        )

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

        panel.contentView = metalView
        panel.delegate = self

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelX = visibleFrame.maxX - width
        let panelY = visibleFrame.maxY - height
        panel.setFrame(NSRect(x: panelX, y: panelY, width: width, height: height), display: true)

        panel.makeKeyAndOrderFront(nil)

        Task {
            await audioScanner.startCapture()
        }
    }

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
