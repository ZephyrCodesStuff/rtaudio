//
//  rtaudioApp.swift
//  rtaudio
//
//  Created by zeph on 10/03/26.
//

import SwiftUI
import AppKit

@main
struct rtaudioApp: App {
    // Hooks into AppKit to manage the NSPanel manually
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use Settings to ensure no default window is created
        Settings {
            EmptyView()
        }
    }
}
