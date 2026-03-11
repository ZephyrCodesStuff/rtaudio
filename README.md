<div align="center">

  <h1>🌊 rtaudio</h1>

  <p>
    <strong>A hyper-optimized, GPU-accelerated macOS system audio visualizer inspired by Apple's Dynamic Island.</strong>
  </p>

  <p>
    <a href="#license"><img src="https://img.shields.io/badge/license-AGPLv3.0-blue?style=flat-square" alt="License"></a>
  </p>

</div>

---

## 🌟 Authors

- [@zeph](https://github.com/ZephyrCodesStuff) (that's me!)

## 📖 Overview

**rtaudio** is a computationally invisible, real-time macOS system audio visualizer. It drops deep into the macOS hardware stack to capture targeted application audio via kernel-level CoreAudio taps, performs a hardware-accelerated Fast Fourier Transform (FFT) in C++, and renders a buttery-smooth waveform entirely on the GPU using custom Metal fragment shaders.

> ℹ️ **Info**: `rtaudio` is _not really a "final product"_ but more of a _highly-optimized proof-of-concept_ for real-time audio visualization on macOS.
>
> The app bypasses SwiftUI entirely to avoid `AttributeGraph` diffing overhead. The real magic is how it hands 100% of the UI rendering to the GPU, making it possible to run an accurate remake of Apple's waveform visualizer, at near-zero CPU cost; even on battery power.
>
> **Feel free to include its techniques in your own project** (but _please give credit!_)

## ⚡ Performance

`rtaudio` is engineered to be a **zero-overhead background utility**. It blends seamlessly into your system's idle baseline, making it perfect for "Dynamic Island" style overlays that run constantly on MacBooks without draining the battery.

Benchmarks using "Release" build mode currently show:

- **CPU Usage**: Effectively **< 1%** CPU cycle usage (Instruments) and ~2.2% Wall Clock time while actively rendering at 30 FPS.
- **Pause when Unused**: Hooks into `NSWindow.occlusionState` to automatically freeze the CoreAudio tap and Metal draw loop the millisecond the visualizer is covered or the screen locks, dropping usage to absolute **0.0%**.
- **Audio Processing**: Accelerate (`vDSP`) SIMD operations process 1024-sample mono FFTs and peak detection in fractions of a millisecond.
- **Rendering**: Bypasses Apple's 2D path-drawing entirely. The waveform is drawn using mathematically perfect Signed Distance Fields (SDFs) directly in a Metal Fragment Shader.

## 🔧 Features & Tech Stack

### Core Features

| Feature                    | Description                                                                                                                           |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------------------------ |
| **Dynamic Island Physics** | 4-band frequency separation with asymmetric Attack/Release physics and 60 FPS Linear Interpolation (Lerp) tuned for raw audio.        |
| **SDF Metal Shaders**      | Bypasses the CPU for UI rendering. GPU calculates waveform pixels in parallel using Signed Distance Fields.                           |
| **CoreAudio PID Hunter**   | Scans `NSWorkspace` for specific running apps (Apple Music, Spotify), translates UNIX PIDs to HAL Object IDs, and taps them directly. |

### Technologies Used

| Component            | Technology                                |
| :------------------- | :---------------------------------------- |
| **Audio Capture**    | `CoreAudio` (`CATap` / Aggregate Devices) |
| **DSP & FFT**        | `Accelerate` / `vDSP` (C++)               |
| **State Management** | `AppKit` (`NSWindowDelegate` occlusion)   |
| **Rendering**        | `Metal` (`MTKView` / MSL Shaders)         |

## 💿 Getting Started

### Prerequisites

- macOS 14.2+ (Required for public `AudioHardwareCreateProcessTap` support)
- Xcode 15+

### Building & Running

1. Clone the repository and open `rtaudio.xcodeproj` in Xcode.
2. Build and Run (`Cmd + R`).

> **Tip:** macOS treats kernel-level audio taps exactly like physical microphones. The OS will automatically prompt you for Microphone permissions on the first run. You may need to restart the app after granting permission!

## 💛 Contributions

Contributions are welcome! Since this project aims for hyper-efficiency:

1. Please ensure any UI additions are written as `MSL` shaders. Do not introduce SwiftUI or Core Animation layers that require CPU geometry calculation.
2. Keep audio processing allocations strictly outside of the C++ `process()` loop to prevent audio dropouts.
3. Make sure your PR contains all the details needed to know what you're changing and why.

## 📄 License

This project is licensed under the **MIT License**.

**What this means:**

- ✅ **You can** use this code in your own projects.
- ✅ **You can** modify the tool to suit your needs.
- ✅ **You can** distribute closed-source versions.

See [LICENSE](LICENSE) for more details.
