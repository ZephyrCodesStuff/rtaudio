//
//  Metal.swift
//  rtaudio
//
//  Created by zeph on 12/03/26.
//

// WARN: this must align perfectly with `struct WaveformParams` in Metal!
struct MetalWaveformParams {
    var magnitudes: (Float, Float, Float, Float)
    var viewportSize: SIMD2<Float>
    var backingScaleFactor: Float
    var colorTop: SIMD3<Float>
    var colorBottom: SIMD3<Float>
}
