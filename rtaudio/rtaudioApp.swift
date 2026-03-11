//
//  rtaudioApp.swift
//  rtaudio
//
//  Created by zeph on 10/03/26.
//

import AppKit
import SwiftUI

@main
struct rtaudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
