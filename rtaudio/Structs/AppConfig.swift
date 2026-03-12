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

    private init() {
        self.frameRate = UserDefaults.standard.integer(forKey: "frameRate")
        if self.frameRate == 0 {
            self.frameRate = 30
        }
    }
}
