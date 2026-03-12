//
//  AudioTap.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import AppKit
import AudioToolbox
import CoreAudio
import simd

// Global variable to hold reference to the current scanner instance
private var gCurrentScanner: AudioTap?

// CoreAudio fires this on a high-priority background real-time thread.
let audioIOProc: AudioDeviceIOProc = {
    inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData in

    guard let clientData = clientData else { return noErr }
    let scanner = Unmanaged<AudioTap>.fromOpaque(clientData).takeUnretainedValue()

    if scanner.isPaused { return noErr }

    let mutableInputData = UnsafeMutablePointer(mutating: inInputData)
    let bufferList = UnsafeMutableAudioBufferListPointer(mutableInputData)

    if let firstBuffer = bufferList.first, let data = firstBuffer.mData {
        // CoreAudio gives us byte size, divide by 4 (Float size) to get array length
        let floatCount = Int32(firstBuffer.mDataByteSize) / Int32(MemoryLayout<Float>.size)

        let floatData = data.assumingMemoryBound(to: Float.self)

        // Pass the mono array directly to C++
        scanner.bridge.processBuffer(floatData, count: floatCount)
    }

    return noErr
}

private func getAudioObjectID(for pid: pid_t) -> AudioObjectID? {
    var audioObjectID: AudioObjectID = kAudioObjectUnknown
    var pidValue = pid

    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let qualifierSize = UInt32(MemoryLayout<pid_t>.size)

    // We query the global system object (kAudioObjectSystemObject)
    // We pass the PID as the "qualifier", and it returns the AudioObjectID
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        qualifierSize,
        &pidValue,
        &size,
        &audioObjectID
    )

    if status == noErr && audioObjectID != kAudioObjectUnknown {
        return audioObjectID
    }

    return nil
}

class AudioTap: NSObject {
    let bridge = AudioBridge()
    var isPaused: Bool = false
    private var displayMagnitudes = simd_float4(0, 0, 0, 0)

    // CoreAudio stuff
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID? = nil
    private var captureIsRunning = false

    // Helper function to smooth out the magnitudes for prettifying purposes
    func getSmoothedMagnitudes() -> simd_float4 {
        // Zero bridging overhead. Just passing 16 bytes of memory.
        let targetLevels = bridge.getMagnitudes()

        let smoothingFactor: Float = 0.4

        // Vector math! This does all 4 calculations simultaneously.
        let difference = targetLevels - displayMagnitudes
        displayMagnitudes += difference * smoothingFactor

        return displayMagnitudes
    }

    func startCapture() async {
        guard !captureIsRunning else { return }

        // TODO: extract these in some way (as long as it's not hardcoded)
        let targetBundleIDs = [
            "com.apple.Music",
            "com.spotify.client",
            "com.apple.Safari",
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        var targetPIDs: [AudioDeviceID] = []

        for app in runningApps {
            if let bundleID = app.bundleIdentifier, targetBundleIDs.contains(bundleID) {
                if let deviceID = getAudioObjectID(for: app.processIdentifier) {
                    targetPIDs.append(deviceID)
                    print(
                        "🎯 Found \(app.localizedName ?? "App") with PID: \(app.processIdentifier)")
                }
            }
        }

        if targetPIDs.isEmpty {
            print("⚠️ None of our target apps are running right now.")
            // TODO: might want to return here or handle gracefully
        }

        let description = CATapDescription()
        description.processes = targetPIDs
        description.isMixdown = true
        description.isMono = true

        tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            print("🛑 Tap Error: \(status)")
            return
        }

        // Get the tap's unique hardware UID
        var tapUID: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.stride)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = withUnsafeMutablePointer(to: &tapUID) { uidPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, uidPtr)
        }
        guard status == noErr else {
            print("🛑 UID Error: \(status)")
            return
        }

        // Create the Aggregate Device (a "virtual microphone" that we can route the tap into)
        let tapList = [[kAudioSubTapUIDKey: tapUID]]
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "RTAudio_Virtual_Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,  // Hides it from the user's sound settings
            kAudioAggregateDeviceTapListKey: tapList,
        ]

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDict as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            print("🛑 Aggregate Error: \(status)")
            return
        }

        // Bind the Callback to the device
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, audioIOProc, selfPointer, &ioProcID)

        guard status == noErr, let validIOProcID = ioProcID else {
            print("🛑 IOProc Error: \(status)")
            return
        }

        // Start listening
        status = AudioDeviceStart(aggregateDeviceID, validIOProcID)
        guard status == noErr else {
            print("🛑 Start Error: \(status)")
            return
        }

        captureIsRunning = true
        print("🟢 CoreAudio CATap flowing through Aggregate Device!")
    }

    func stopCapture() {
        guard captureIsRunning else { return }

        // Stop listening
        if let validIOProcID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, validIOProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, validIOProcID)
        }

        // Destroy resources
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }

        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        captureIsRunning = false

        print("🔴 CoreAudio CATap capture stopped")
    }

    deinit {
        stopCapture()
    }
}
