<div align="center">

  <h1>🌊 rtaudio</h1>

  <p>
    <strong>A hyper-optimized, 60-FPS macOS system audio visualizer inspired by Apple's Dynamic Island.</strong>
  </p>

  <p>
    <a href="#license"><img src="https://img.shields.io/badge/license-AGPLv3.0-blue?style=flat-square" alt="License"></a>
  </p>

</div>

---

## 🌟 Authors

- [@zeph](https://github.com/ZephyrCodesStuff) (that's me!)

## 📖 Overview

**rtaudio** is a real-time macOS system audio visualizer. It captures your Mac's internal audio, performs a hardware-accelerated Fast Fourier Transform (FFT) to isolate frequency bands, and renders a buttery-smooth waveform. As a premium touch, it dynamically masks the visualizer over a blurred, vibrant version of your currently playing Apple Music album artwork.

> ⚠️ **Note**: This tool requires bypassing the macOS App Sandbox to capture system-wide audio and communicate with the Apple Music app via Apple Events.

> ℹ️ **Info**: `rtaudio` is _not really a "final product"_ but more of a _highly-optimized proof-of-concept_ for real-time audio visualization on macOS.
>
> The app itself is just a single SwiftUI view with a custom rendering loop, but the real magic is in how it captures and processes audio with minimal overhead.
>
> **Feel free to include its techniques in your own project!**

## ⚡ Performance

`rtaudio` is engineered to be a **zero-overhead background utility**. It should blend seamlessly into your system's idle baseline.

A good amount of time and effort have been spent optimizing the core pipeline to avoid SwiftUI rendering bottlenecks and massive background video-capture penalties.

Benchmarks using "Release" build mode currently show:

- **CPU Usage**: Added overhead of **< 5%** while actively rendering at 60 FPS.
- **Audio Processing**: Accelerate (`vDSP`) SIMD operations process 1024-sample FFTs and peak detection in fractions of a millisecond.
- **Rendering**: Bypasses `AttributeGraph` entirely using an immediate-mode Metal `Canvas`.

## 🔧 Features & Tech Stack

### Core Features

| Feature                    | Description                                                                                                                         |
| :------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| **Dynamic Island Physics** | 4-band frequency separation with asymmetric Attack/Release physics and 60 FPS Linear Interpolation (Lerp).                          |
| **Zero-Overhead UI**       | Built using SwiftUI's `Canvas` to bypass standard layout diffing and overlapping animation calculations.                            |
| **Starved-Stream Capture** | Exploits `ScreenCaptureKit` by capturing a 16x16 pixel window at 1 FPS to extract system audio without the video-rendering penalty. |
| **Dynamic Album Art**      | Integrates with Apple Events to fetch the active Apple Music track artwork, using the waveform as a clipping mask.                  |

### Technologies Used

| Component            | Technology                            |
| :------------------- | :------------------------------------ |
| **Audio Capture**    | `ScreenCaptureKit` (Swift)            |
| **DSP & FFT**        | `Accelerate` / `vDSP` (C++)           |
| **State Management** | `Combine` (Timer-based UI throttling) |
| **Rendering**        | SwiftUI `Canvas` (Metal-backed)       |

## 💿 Getting Started

### Prerequisites

- macOS 14.0+ (Required for `Canvas` and specific `ScreenCaptureKit` features)
- Xcode 15+

### Building & Running

1. Clone the repository and open `rtaudio.xcodeproj` in Xcode.
2. **Disable the App Sandbox:**
   - Go to your Target > **Signing & Capabilities**.
   - Click the Trash icon next to **App Sandbox** to remove it.
3. **Set Privacy Permissions:** \* Go to your Target > **Info**.
   - Add the key `Privacy - AppleEvents Sending Usage Description` with a value like: _"We need to see what's playing to grab the album art."_
4. Build and Run (`Cmd + R`).

> **Tip:** macOS will automatically prompt you for Screen Recording permissions on the first run to allow `ScreenCaptureKit` to grab the system audio.

## 💛 Contributions

Contributions are welcome! Since this project aims for hyper-efficiency:

1. Please ensure any UI additions do not re-introduce `AttributeGraph` bottlenecks (prefer `Canvas` drawing).
2. Keep audio processing allocations strictly outside of the `process()` loop to prevent audio dropouts.
3. Make sure your PR contains all the details needed to know what you're changing and why.

## 📄 License

This project is licensed under the **MIT License**.

**What this means:**

- ✅ **You can** use this code in your own projects.
- ✅ **You can** modify the tool to suit your needs.
- ✅ **You can** distribute closed-source versions.

See [LICENSE](LICENSE) for more details.
