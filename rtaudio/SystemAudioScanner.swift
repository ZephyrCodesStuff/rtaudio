//
//  SystemAudioScanner.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import ScreenCaptureKit


class SystemAudioScanner: NSObject, SCStreamOutput {
    private let bridge = AudioBridge()
    private var stream: SCStream?
    
    // Turned on while window isn't active
    var isPaused: Bool = false

    // Internal state for smoothing
    private var displayMagnitudes: [Float] = [0, 0, 0, 0]

    // The Canvas will call this 60 to 120 times a second
    func getSmoothedMagnitudes() -> [Float] {
        guard let targetLevels = bridge.getMagnitudes() as? [Float] else {
            return displayMagnitudes
        }
        
        let smoothingFactor: Float = 0.4
        
        for i in 0..<4 {
            let difference = targetLevels[i] - displayMagnitudes[i]
            displayMagnitudes[i] += difference * smoothingFactor
        }
        
        return displayMagnitudes
    }

    func startCapture() async {
        do {
            // 1. Get shareable content (all apps/displays)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            // 2. Create a filter for system audio
            let filter = SCContentFilter(display: content.displays[0], excludingApplications: [], exceptingWindows: [])
            
            // 3. Configure for Audio Only
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            // 🛑 STARVE THE VIDEO CAPTURE
            // Force the background video engine to do basically zero work.
            config.width = 16
            config.height = 16
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 Frame Per Second
            config.showsCursor = false
            
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // 4. Add the output listener
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            try await stream?.startCapture()
            
        } catch {
            print("Failed to capture system audio: \(error)")
        }
    }

    // This is the "Tap" equivalent for System Audio
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, !isPaused else { return }
        
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            if let rawPointer = dataPointer {
                let floatPointer = rawPointer.withMemoryRebound(to: Float.self, capacity: length / 4) { $0 }
                
                bridge.processBuffer(floatPointer, count: Int32(length / 4))
            }
        }
    }
}
