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
        // HStack defaults to center alignment, which is what we want!
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                let rawValue = magnitudes[index]
                let height = CGFloat(rawValue * 50) + 5

                Capsule()
                    .frame(width: 6, height: min(height, 160))
                    .animation(.linear(duration: 0.05), value: height)
            }
        }
        // LOCK the height of the container to your maximum capsule height
        .frame(height: 160)
        .drawingGroup()
    }
}

class SystemAudioScanner: NSObject, SCStreamOutput, ObservableObject {
    private let bridge = AudioBridge()
    private var stream: SCStream?
    @Published var magnitudes: [Float] = [0, 0, 0, 0]

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
            
//            // We don't have our own audio anyway
//            config.excludesCurrentProcessAudio = true
            
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
                
                // Update UI
                let levels = bridge.getMagnitudes() as? [Float] ?? [0, 0, 0, 0]
                DispatchQueue.main.async {
                    self.magnitudes = levels
                }
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
 
