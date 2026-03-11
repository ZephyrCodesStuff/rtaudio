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

func makeCornerMask(size: CGSize) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
        let bezierPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.black.set()
        bezierPath.fill()
        return true
    }
    return image
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel!
    let audioScanner = SystemAudioScanner()
    var metalView: WaveformMTKView!

    let width: CGFloat = 135
    let height: CGFloat = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.blendingMode = .behindWindow // Blurs the desktop/apps behind the panel
        visualEffect.material = .hudWindow        // Dark, high-contrast frosted glass
        visualEffect.state = .active              // Keep it blurred even when not in focus
        visualEffect.maskImage = makeCornerMask(size: CGSize(width: width, height: height)) // Round the whole island
        
        metalView = WaveformMTKView(frame: visualEffect.bounds, audio: audioScanner)
        metalView.autoresizingMask = [.width, .height]
        
        visualEffect.addSubview(metalView)
        panel.contentView = visualEffect
        
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
