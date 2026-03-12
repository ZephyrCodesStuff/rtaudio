//
//  AppConfig.swift
//  rtaudio
//
//  Created by zeph on 12/03/26.
//

import Foundation

@Observable
final class AppConfig {
    static let shared = AppConfig()

    static let frameRateOptions = [30, 60, 120]

    var frameRate: Int {
        didSet {
            UserDefaults.standard.set(frameRate, forKey: "frameRate")
        }
    }

    var windowPositionX: Double {
        didSet {
            UserDefaults.standard.set(windowPositionX, forKey: "windowPositionX")
        }
    }

    var windowPositionY: Double {
        didSet {
            UserDefaults.standard.set(windowPositionY, forKey: "windowPositionY")
        }
    }

    private init() {
        self.frameRate = UserDefaults.standard.integer(forKey: "frameRate")
        self.windowPositionX = UserDefaults.standard.double(forKey: "windowPositionX")
        self.windowPositionY = UserDefaults.standard.double(forKey: "windowPositionY")

        if self.frameRate == 0 {
            self.frameRate = 30
        }
    }
}
