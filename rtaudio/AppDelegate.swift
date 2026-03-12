//
//  AppDelegate.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import AVFAudio
import Cocoa
internal import MetalKit
import simd

func getAppleMusicArtwork() -> NSImage? {
    let script = """
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            end try
        end tell
        """

    // Apple Music returns the actual image data
    guard let event = getArtwork(script: script) else { return nil }
    
    return NSImage(data: event.data)
}

func getSpotifyArtwork() async -> NSImage? {
    let script = "tell application \"Spotify\" to artwork url of current track"

    // Spotify returns the URL of the art
    guard let event = getArtwork(script: script),
          let urlString = event.stringValue,
          let url = URL(string: urlString) else { 
        print("🎨 Failed to get or parse Spotify artwork URL")
        return nil 
    }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        if let image = NSImage(data: data) {
            print("🎨 Successfully loaded Spotify artwork")
            return image
        } else {
            print("🎨 Failed to create NSImage from Spotify URL data")
        }
    } catch {
        print("🎨 Failed to fetch Spotify artwork: \(error)")
    }

    return nil
}

/// Utility to call an AppleScript and return the result
func getArtwork(script: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        let output = appleScript.executeAndReturnError(&error)

        if let error = error {
            print("🍎 AppleScript Blocked/Failed: \(error)")
            return nil
        }

        return output
    }

    return nil
}

/// Detect which music player is currently playing
///
/// Checks each player to see if it's actively playing.
/// Returns the player that has playback state = playing.
func detectActivePlayer() -> String? {
    for player in ["Music", "Spotify"] {
        let script: String
        if player == "Music" {
            script = """
                try
                    tell application "Music"
                        if player state is playing then
                            return true
                        end if
                    end tell
                end try
                return false
                """
        } else {
            script = """
                try
                    tell application "Spotify"
                        if player state is playing then
                            return true
                        end if
                    end tell
                end try
                return false
                """
        }

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let descriptor = appleScript.executeAndReturnError(&error)

            // Skip this player if there's an error (app not running, sandboxing issues, etc)
            if error != nil {
                print("🎨 No access to \(player) player state")
                continue
            }

            // Check if the player returned true (is playing)
            if descriptor.booleanValue {
                print("🎨 Detected active player: \(player)")
                return player
            }
        }
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

extension NSImage {
    func getGradientColors() -> (SIMD3<Float>, SIMD3<Float>) {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            return (SIMD3(1, 1, 1), SIMD3(0.5, 0.5, 0.5))
        }

        // Sample from top-left and bottom-right corners for better gradient
        let color1 = bitmap.colorAt(x: 10, y: bitmap.pixelsHigh - 10)
        let color2 = bitmap.colorAt(x: bitmap.pixelsWide - 10, y: 10)

        let c1 = ensureVisible(
            SIMD3<Float>(
                Float(color1?.redComponent ?? 1),
                Float(color1?.greenComponent ?? 1),
                Float(color1?.blueComponent ?? 1)))

        let c2 = ensureVisible(
            SIMD3<Float>(
                Float(color2?.redComponent ?? 0.5),
                Float(color2?.greenComponent ?? 0.5),
                Float(color2?.blueComponent ?? 0.5)))

        print("🎨 Color1: R=\(c1.x) G=\(c1.y) B=\(c1.z)")
        print("🎨 Color2: R=\(c2.x) G=\(c2.y) B=\(c2.z)")

        return (c1, c2)
    }

    private func ensureVisible(_ color: SIMD3<Float>, minLuminance: Float = 0.25) -> SIMD3<Float> {
        // These values are not random:
        //  the human eye perceives brightness according to these ratios,
        //  so we need to take them into account when calculating luminance.
        let luminance = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
        guard luminance > 0, luminance < minLuminance else { return color }
        let scaled = color * (minLuminance / luminance)
        return simd_min(scaled, SIMD3<Float>(1, 1, 1))
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: NSPanel!
    let audioTap = AudioTap()
    var metalView: WaveformMTKView!

    let width: CGFloat = 135
    let height: CGFloat = 60
    let offsetX: CGFloat = 10
    let offsetY: CGFloat = 10

    // Menu bar entry
    var statusItem: NSStatusItem!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize a Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // TODO: custom icon (now we're using SF Symbols for convenience)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform", accessibilityDescription: "rtaudio")
        }

        let menu = NSMenu()

        // Frame Rate submenu
        let frameRateMenu = NSMenu()
        for frameRate in AppConfig.frameRateOptions {
            let item = NSMenuItem(
                title: "\(frameRate) FPS",
                action: #selector(setFrameRate(_:)),
                keyEquivalent: ""
            )
            item.tag = frameRate
            item.state = AppConfig.shared.frameRate == frameRate ? .on : .off
            item.target = self
            frameRateMenu.addItem(item)
        }

        let frameRateItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        frameRateItem.submenu = frameRateMenu
        menu.addItem(frameRateItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit rtaudio",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusItem.menu = menu

        // Create the actual app panel
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
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let backing = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        backing.wantsLayer = true
        backing.layer?.backgroundColor = NSColor.black.cgColor
        backing.layer?.cornerRadius = 12
        backing.layer?.borderWidth = 0.5
        backing.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        backing.layer?.shadowColor = NSColor.black.cgColor
        backing.layer?.shadowOpacity = 0.5
        backing.layer?.shadowRadius = 2
        backing.layer?.shadowOffset = CGSize(width: 0, height: -1)

        metalView = WaveformMTKView(frame: backing.bounds, audio: audioTap)
        metalView.autoresizingMask = [.width, .height]

        backing.addSubview(metalView)
        panel.contentView = backing

        panel.delegate = self

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Restore window position or use default
        var panelX = AppConfig.shared.windowPositionX
        var panelY = AppConfig.shared.windowPositionY

        if panelX == 0 && panelY == 0 {
            // No saved position, use default (top-right corner)
            panelX = visibleFrame.maxX - width - offsetX
            panelY = visibleFrame.maxY - height - offsetY
        }

        panel.setFrame(NSRect(x: panelX, y: panelY, width: width, height: height), display: true)

        panel.makeKeyAndOrderFront(nil)

        setupMusicObserver()
        updateArtworkColor()

        Task {
            await audioTap.startCapture()
        }
    }

    func setupMusicObserver() {
        // Listen to Apple Music notifications
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { _ in
            self.updateArtworkColor()
        }

        // Listen to Spotify notifications
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { _ in
            self.updateArtworkColor()
        }
    }

    func updateArtworkColor() {
        // Wrap in a background Task so the AppleScript doesn't hang the UI thread
        Task(priority: .background) {
            guard let activePlayer = detectActivePlayer() else {
                print("🎨 No music player detected")
                return
            }

            let image: NSImage?
            if activePlayer == "Music" {
                image = getAppleMusicArtwork()
            } else if activePlayer == "Spotify" {
                image = await getSpotifyArtwork()
            } else {
                image = nil
            }

            guard let image = image else {
                print("🎨 Failed to get artwork from \(activePlayer)")
                return
            }

            let (top, bottom) = image.getGradientColors()
            print("🎨 Extracted colors from \(activePlayer) - Top: \(top), Bottom: \(bottom)")

            // Push the colors to the Metal View once
            await MainActor.run {
                self.metalView.updateColors(top: top, bottom: bottom)
            }
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window.occlusionState.contains(.visible) {
            audioTap.isPaused = false
            metalView.isVisualizerPaused = false
        } else {
            audioTap.isPaused = true
            metalView.isVisualizerPaused = true
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        AppConfig.shared.windowPositionX = frame.origin.x
        AppConfig.shared.windowPositionY = frame.origin.y
    }

    @objc func setFrameRate(_ sender: NSMenuItem) {
        let frameRate = sender.tag
        AppConfig.shared.frameRate = frameRate

        // Update menu item checkmarks
        if let menu = statusItem.menu {
            if let frameRateSubmenu = menu.item(withTitle: "Frame Rate")?.submenu {
                for item in frameRateSubmenu.items {
                    item.state = frameRate == item.tag ? .on : .off
                }
            }
        }

        // Apply frame rate to the Metal view
        metalView.preferredFramesPerSecond = frameRate
    }
}
