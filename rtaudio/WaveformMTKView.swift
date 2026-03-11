//
//  WaveformMTKView.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import Cocoa
import MetalKit

// WARN: this must align perfectly with `struct WaveformParams` in Metal!
struct MetalWaveformParams {
    var magnitudes: (Float, Float, Float, Float)
    var viewportSize: SIMD2<Float>
}

class WaveformMTKView: MTKView, MTKViewDelegate {
    var audio: SystemAudioScanner!
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?

    // We use this to manually pause the draw loop from the AppDelegate
    var isVisualizerPaused: Bool = false {
        didSet { self.isPaused = isVisualizerPaused }
    }

    init(frame: CGRect, audio: SystemAudioScanner) {
        self.audio = audio

        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())

        self.delegate = self
        self.layerContentsRedrawPolicy = .duringViewResize
        self.layer?.isOpaque = false
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.preferredFramesPerSecond = 30
        self.enableSetNeedsDisplay = false

        // Only draw after init is done, prevents a little spike
        self.isPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isPaused = false
        }

        setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupMetal() {
        guard let device = self.device else { return }
        self.commandQueue = device.makeCommandQueue()

        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "waveform_vertex")
        let fragmentFunction = library?.makeFunction(name: "waveform_fragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        if let colorAttachment = pipelineDescriptor.colorAttachments[0] {
            colorAttachment.pixelFormat = .bgra8Unorm
            colorAttachment.isBlendingEnabled = true
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("🛑 METAL PIPELINE CRASH: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if isVisualizerPaused { return }

        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let pipelineState = pipelineState,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        let mags = audio.getSmoothedMagnitudes()

        var params = MetalWaveformParams(
            magnitudes: (mags[0], mags[1], mags[2], mags[3]),
            viewportSize: SIMD2<Float>(
                Float(view.drawableSize.width), Float(view.drawableSize.height))
        )

        renderEncoder.setFragmentBytes(
            &params, length: MemoryLayout<MetalWaveformParams>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }
}
