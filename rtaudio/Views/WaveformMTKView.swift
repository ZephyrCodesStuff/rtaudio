//
//  WaveformMTKView.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import Cocoa
import MetalKit

class WaveformMTKView: MTKView, MTKViewDelegate {
    var audio: AudioTap!
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?

    // Color transitioning
    private var colorTop = SIMD3<Float>(1, 1, 1)
    private var colorBottom = SIMD3<Float>(1, 1, 1)
    private var targetTop = SIMD3<Float>(1, 1, 1)
    private var targetBottom = SIMD3<Float>(1, 1, 1)
    private var needsColorTransition = false

    // Dragging state
    private var isDragging = false
    private var dragStart: NSPoint = .zero
    private var trueOriginalWindowSize: CGSize = .zero
    private var originalSizeInitialized = false

    func updateColors(top: SIMD3<Float>, bottom: SIMD3<Float>) {
        targetTop = top
        targetBottom = bottom
        needsColorTransition = true
    }

    func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }

    var isVisualizerPaused: Bool = false {
        didSet { self.isPaused = isVisualizerPaused }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        self.window?.invalidateCursorRects(for: self)
        dragStart = event.locationInWindow

        guard let window = self.window else { return }

        if !originalSizeInitialized {
            trueOriginalWindowSize = window.frame.size
            originalSizeInitialized = true
        }

        let scaleFactor: CGFloat = 0.92
        let centerX = window.frame.midX
        let centerY = window.frame.midY
        let newWidth = window.frame.width * scaleFactor
        let newHeight = window.frame.height * scaleFactor
        let newX = centerX - newWidth / 2
        let newY = centerY - newHeight / 2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window else { return }

        let currentLocation = event.locationInWindow
        let delta = NSPoint(
            x: currentLocation.x - dragStart.x,
            y: currentLocation.y - dragStart.y
        )

        let frame = window.frame
        window.setFrame(
            NSRect(
                x: frame.origin.x + delta.x, y: frame.origin.y + delta.y, width: frame.width,
                height: frame.height),
            display: true
        )
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        self.window?.invalidateCursorRects(for: self)

        guard let window = self.window else { return }

        let currentFrame = window.frame
        let centerX = currentFrame.midX
        let centerY = currentFrame.midY
        let newX = centerX - trueOriginalWindowSize.width / 2
        let newY = centerY - trueOriginalWindowSize.height / 2

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(
                NSRect(
                    x: newX, y: newY, width: trueOriginalWindowSize.width,
                    height: trueOriginalWindowSize.height), display: true)
        }
    }

    init(frame: CGRect, audio: AudioTap) {
        self.audio = audio
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())

        self.delegate = self
        self.isPaused = false  // Let MTKView drive!
        self.enableSetNeedsDisplay = false

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
        let mags = audio.getSmoothedMagnitudes()
        let activity = mags.reduce(0, +)

        // If there is no audio and no animation happening, we return immediately.
        // Because we don't call `currentDrawable`, Metal does 0 GPU work this frame.
        if activity < 0.0001 && !needsColorTransition {
            return
        }

        // This is mandatory for 120Hz loops to prevent CPU memory thrashing
        autoreleasepool {
            guard let commandBuffer = commandQueue?.makeCommandBuffer(),
                let renderPassDescriptor = view.currentRenderPassDescriptor,
                let pipelineState = pipelineState,
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                    descriptor: renderPassDescriptor)
            else { return }

            renderEncoder.setRenderPipelineState(pipelineState)

            if needsColorTransition {
                colorTop = mix(colorTop, targetTop, t: 0.05)
                colorBottom = mix(colorBottom, targetBottom, t: 0.05)

                if distance(colorTop, targetTop) < 0.001
                    && distance(colorBottom, targetBottom) < 0.001
                {
                    colorTop = targetTop
                    colorBottom = targetBottom
                    needsColorTransition = false
                }
            }

            let scaleFactor = (self.drawableSize.width / self.bounds.width) * 0.7
            var params = MetalWaveformParams(
                magnitudes: (mags[0], mags[1], mags[2], mags[3]),
                viewportSize: SIMD2<Float>(
                    Float(view.drawableSize.width), Float(view.drawableSize.height)),
                backingScaleFactor: Float(scaleFactor),
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
}
