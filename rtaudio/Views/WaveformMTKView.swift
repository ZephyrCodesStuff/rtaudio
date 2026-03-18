//
//  WaveformMTKView.swift
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

import Cocoa
import Metal
import QuartzCore
import simd

class WaveformMTKView: NSView, CAMetalDisplayLinkDelegate {
    var audio: AudioTap!
    private var metalLayer: CAMetalLayer!
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private var displayLink: CAMetalDisplayLink?

    // 🔥 1. The new Background Thread
    private var renderThread: Thread?
    private var hasRenderedBlankFrame = false
    private var idleFrameCount = 0
    private let idleFrameThreshold = 10  // ~330ms at 30fps

    // 🔥 2. Thread-safe cached geometry
    private var geometryLock = os_unfair_lock_s()
    private var _cachedViewport = SIMD2<Float>(0, 0)
    private var _cachedScaleFactor: Float = 1.0

    private var cachedGeometry: (viewport: SIMD2<Float>, scale: Float) {
        get {
            os_unfair_lock_lock(&geometryLock)
            let v = _cachedViewport
            let s = _cachedScaleFactor
            os_unfair_lock_unlock(&geometryLock)
            return (v, s)
        }
        set {
            os_unfair_lock_lock(&geometryLock)
            _cachedViewport = newValue.viewport
            _cachedScaleFactor = newValue.scale
            os_unfair_lock_unlock(&geometryLock)
        }
    }

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
        didSet { displayLink?.isPaused = isVisualizerPaused }
    }

    var preferredFramesPerSecond: Int = 30 {
        didSet {
            let fps = Float(preferredFramesPerSecond)
            renderThread.map { thread in
                // perform(_:on:) executes on that thread's runloop
                perform(#selector(applyFrameRate(_:)),
                        on: thread,
                        with: fps as NSNumber,
                        waitUntilDone: false)
            }
        }
    }
    
    @objc private func applyFrameRate(_ fps: NSNumber) {
        let f = fps.floatValue
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: f, maximum: f, preferred: f)
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

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let frameRateMenu = NSMenu()
        for frameRate in AppConfig.frameRateOptions {
            let item = NSMenuItem(
                title: "\(frameRate) FPS",
                action: #selector(AppDelegate.setFrameRate(_:)),
                keyEquivalent: ""
            )
            item.tag = frameRate
            item.state = AppConfig.shared.frameRate == frameRate ? .on : .off
            item.target = NSApp.delegate
            frameRateMenu.addItem(item)
        }

        let frameRateItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        frameRateItem.submenu = frameRateMenu
        menu.addItem(frameRateItem)

        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(
            title: "Reset Position",
            action: #selector(AppDelegate.resetWindowPosition),
            keyEquivalent: ""
        )
        resetItem.target = NSApp.delegate
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = NSApp.delegate
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit rtaudio",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: ""
            ))

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    init(frame: CGRect, audio: AudioTap) {
        self.audio = audio
        super.init(frame: frame)

        // 3. Safer Layer Setup (bypasses makeBackingLayer entirely)
        self.layer = CAMetalLayer()
        self.wantsLayer = true
        self.metalLayer = self.layer as? CAMetalLayer

        setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        metalLayer.contentsScale = scale

        let newWidth = bounds.width * scale
        let newHeight = bounds.height * scale
        metalLayer.drawableSize = CGSize(width: newWidth, height: newHeight)

        let geo = (SIMD2<Float>(Float(newWidth), Float(newHeight)),
                   bounds.width > 0 ? Float((newWidth / bounds.width) * 0.7) : 1.0)
        cachedGeometry = geo
    }
    
    private func setupPipeline(device: MTLDevice) {
        let library = device.makeDefaultLibrary()
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library?.makeFunction(name: "waveform_vertex")
        pipelineDescriptor.fragmentFunction = library?.makeFunction(name: "waveform_fragment")

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
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("🛑 METAL PIPELINE CRASH: \(error)")
        }
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError() }
        commandQueue = device.makeCommandQueue()

        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        setupPipeline(device: device)
        startRenderThread()
    }
    
    private func startRenderThread() {
        renderThread = Thread { [weak self] in
            guard let self else { return }

            let fps = Float(AppConfig.shared.frameRate)
            let dl = CAMetalDisplayLink(metalLayer: self.metalLayer)
            dl.delegate = self
            dl.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(AppConfig.frameRateOptions.first!),
                maximum: Float(AppConfig.frameRateOptions.last!),
                preferred: fps)
            dl.add(to: .current, forMode: .default)

            // Store before running — isPaused setter needs it
            DispatchQueue.main.async { self.displayLink = dl }

            RunLoop.current.run()
        }
        renderThread?.name = "WaveformRenderThread"
        renderThread?.qualityOfService = .userInteractive
        renderThread?.start()
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let mags = audio.getSmoothedMagnitudes()
        let activity = mags.sum()
        let isIdle = activity < 0.0001 && !needsColorTransition

        // True idle: don't touch the drawable at all
        if isIdle {
            idleFrameCount += 1
            if idleFrameCount >= idleFrameThreshold {
                displayLink?.isPaused = true  // zero CPU until audio resumes
            }
            if hasRenderedBlankFrame { return }
            hasRenderedBlankFrame = true
        } else {
            idleFrameCount = 0
            displayLink?.isPaused = false
            hasRenderedBlankFrame = false
        }

        autoreleasepool {
            let currentGeo = cachedGeometry
            var params: MetalWaveformParams?

            if !isIdle {
                updateColors()
                params = MetalWaveformParams(
                    magnitudes: mags,
                    viewportSize: currentGeo.viewport,
                    backingScaleFactor: currentGeo.scale,
                    colorTop: colorTop,
                    colorBottom: colorBottom
                )
            }

            // Acquire drawable as late as possible — minimises stall window
            guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            // NOW access the drawable
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = update.drawable.texture
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].storeAction = .store

            if let pipelineState,
               let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {

                renderEncoder.setRenderPipelineState(pipelineState)
                renderEncoder.setFragmentBytes(&params,
                    length: MemoryLayout<MetalWaveformParams>.stride,
                    index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                renderEncoder.endEncoding()
            }

            commandBuffer.present(update.drawable)
            commandBuffer.commit()
        }
    }
    
    private func updateColors() {
        guard needsColorTransition else { return }
        colorTop    = mix(colorTop,    targetTop,    t: 0.05)
        colorBottom = mix(colorBottom, targetBottom, t: 0.05)

        if distance(colorTop, targetTop) < 0.001 && distance(colorBottom, targetBottom) < 0.001 {
            colorTop    = targetTop
            colorBottom = targetBottom
            needsColorTransition = false
        }
    }
}
