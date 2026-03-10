//
//  ContentView.swift
//  rtaudio
//
//  Created by zeph on 10/03/26.
//

import SwiftUI
import AVFAudio
import ScreenCaptureKit
internal import Combine

struct WaveformView: View {
    let magnitudes: [Float]
    
    var body: some View {
        // Canvas gives you a drawing context and the available size
        Canvas { context, size in
            let barWidth: CGFloat = 6
            let spacing: CGFloat = 8
            let totalBands = 4
            
            // Calculate where to start drawing so the 4 bars are perfectly centered horizontally
            let totalWidth = CGFloat(totalBands) * barWidth + CGFloat(totalBands - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            
            for index in 0..<totalBands {
                let rawValue = magnitudes[index]
                let height = min(CGFloat(rawValue * 50) + 5, 160)
                
                // Calculate X and Y to perfectly center the bar vertically and horizontally
                let x = startX + CGFloat(index) * (barWidth + spacing)
                let y = (size.height - height) / 2
                
                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                
                // Draw a rounded rectangle (equivalent to your Capsule)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                
                // Fill it with a color (change this to whatever matches your app!)
                context.fill(path, with: .color(.white)) 
            }
        }
        // Lock the frame height, just like before
        .frame(height: 160)
        
        // 🛑 Notice what's missing: 
        // No .drawingGroup() needed (Canvas uses Metal natively)
        // No .animation() needed (Our C++ decayRates do the smoothing!)
    }
}   

class SystemAudioScanner: NSObject, SCStreamOutput, ObservableObject {
    private let bridge = AudioBridge()
    private var stream: SCStream?
    private var timer: AnyCancellable?

    private var displayMagnitudes: [Float] = [0, 0, 0, 0]
    @Published var magnitudes: [Float] = [0, 0, 0, 0]

    override init() {
        super.init()

        // Timer fires at ~60 FPS
        timer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateUI()
            }
    }

    private func updateUI() {
        // The UI gently pulls the data precisely when it's ready to draw it, 
        // rather than the audio thread aggressively pushing it.
        if let targetLevels = bridge.getMagnitudes() as? [Float] {
            
            // LERP Factor: 1.0 is instant snap. 0.1 is very slow and gooey.
            // 0.35 to 0.45 is usually the "Dynamic Island" sweet spot!
            let smoothingFactor: Float = 0.4
            
            for i in 0..<4 {
                // 1. Find the distance between where the bar IS and where it NEEDS to be
                let difference = targetLevels[i] - displayMagnitudes[i]
                
                // 2. Move only a percentage of that distance this frame
                displayMagnitudes[i] += difference * smoothingFactor
            }
            
            // Publish the perfectly interpolated numbers to the Canvas
            self.magnitudes = displayMagnitudes
        }
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
        guard type == .audio else { return }
        
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

struct ContentView: View {
    @StateObject private var audio = SystemAudioScanner() // The class we wrote earlier

        var body: some View {
            VStack {
                WaveformView(magnitudes: audio.magnitudes)
                    .frame(height: 200)
                
                Button("Start Visualizer") {
                    Task { await audio.startCapture() }
                }
            }
            .padding()
        }
}

#Preview {
    ContentView()
}
 
