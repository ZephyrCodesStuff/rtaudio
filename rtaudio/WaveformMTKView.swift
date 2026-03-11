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
    var backingScaleFactor: Float
    var colorTop: SIMD3<Float>  // 🎨 Primary
    var colorBottom: SIMD3<Float>  // 🎨 Secondary
}

class WaveformMTKView: MTKView, MTKViewDelegate {
    var audio: SystemAudioScanner!
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?

    // Pretty album art-based coloring and transitioning
    private var colorTop = SIMD3<Float>(1, 1, 1)
    private var colorBottom = SIMD3<Float>(1, 1, 1)
    private var targetTop = SIMD3<Float>(1, 1, 1)
    private var targetBottom = SIMD3<Float>(1, 1, 1)
    private var needsColorTransition = false  // lazy, please!

    // Used to sync UI drawing with the screen's refresh rate
    private var displayLink: CADisplayLink?

    func updateColors(top: SIMD3<Float>, bottom: SIMD3<Float>) {
        targetTop = top
        targetBottom = bottom
        needsColorTransition = true
    }

    func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }

    // We use this to manually pause the draw loop from the AppDelegate
    var isVisualizerPaused: Bool = false {
        didSet { self.isPaused = isVisualizerPaused }
    }

    @objc private func renderTick(sender: CADisplayLink) {
        // Check if we actually need to draw (Silence check)
        let mags = audio.getSmoothedMagnitudes()
        let activity = mags.reduce(0, +)

        // Only trigger a draw if music is playing or colors are fading
        if activity > 0.0001 || needsColorTransition {
            self.draw(in: self)

            displayLink = self.window?.screen?.displayLink(
                target: self, selector: #selector(renderTick))

            // 3. Add to the main run loop so it fires alongside UI updates
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    // User might move the window from a display to another:
    // we need to renew the refresh rate since it might be outdated
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        displayLink?.invalidate()
    }

    init(frame: CGRect, audio: SystemAudioScanner) {
        self.audio = audio
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())

        // Set delegate before configuring draw modes
        self.delegate = self

        // Manually control drawing via DisplayLink instead of the internal timer
        self.isPaused = true
        self.enableSetNeedsDisplay = false  // We will call draw(in:) directly

        self.layerContentsRedrawPolicy = .duringViewResize
        self.layer?.isOpaque = false
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

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
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
            let renderPassDescriptor = self.currentRenderPassDescriptor,
            let pipelineState = pipelineState,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }

        renderEncoder.setRenderPipelineState(pipelineState)

        let mags = audio.getSmoothedMagnitudes()

        if needsColorTransition {
            // Smoothly interpolate
            colorTop = mix(colorTop, targetTop, t: 0.05)
            colorBottom = mix(colorBottom, targetBottom, t: 0.05)

            // If we are close enough to the target, snap and stop
            if distance(colorTop, targetTop) < 0.001 && distance(colorBottom, targetBottom) < 0.001
            {
                colorTop = targetTop
                colorBottom = targetBottom
                needsColorTransition = false
                print("🎨 Color transition complete. Math suspended.")
            }
        }

        var params = MetalWaveformParams(
            magnitudes: (mags[0], mags[1], mags[2], mags[3]),
            viewportSize: SIMD2<Float>(
                Float(view.drawableSize.width), Float(view.drawableSize.height)),
            backingScaleFactor: Float(self.layer?.contentsScale ?? 1.0) * 1.5,
            colorTop: colorTop,
            colorBottom: colorBottom
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
