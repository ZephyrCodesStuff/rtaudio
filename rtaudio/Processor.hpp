//
//  Processor.hpp
//  rtaudio
//
//  Created by zeph on 10/03/26.
//

#ifndef Processor_hpp
#define Processor_hpp

#include <Accelerate/Accelerate.h>
#include <cmath>
#include <vector>

class AudioProcessor {
private:
  FFTSetup fftSetup;
  vDSP_Length log2n;
  int n, nOver2;
  int writePos = 0; // how many mono samples have been buffered

  // Pre-allocated buffers to prevent audio dropouts (no mallocs in process
  // loop!)
  std::vector<float> mono;
  std::vector<float> window;
  std::vector<float> real;
  std::vector<float> imag;
  std::vector<float> fftMags;

public:
  float magnitudes[4] = {0, 0, 0, 0};
  float prevMagnitudes[4] = {0, 0, 0, 0};

  AudioProcessor() {
    // Set up for a 1024-sample FFT
    n = 1024;
    log2n = log2f(n);
    nOver2 = n / 2;
    fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);

    mono.resize(n);
    window.resize(n);
    real.resize(nOver2);
    imag.resize(nOver2);
    fftMags.resize(nOver2);

    // Pre-calculate Hann window
    vDSP_hann_window(window.data(), n, vDSP_HANN_NORM);
  }

  ~AudioProcessor() { vDSP_destroy_fftsetup(fftSetup); }

  void process(const float *buffer, int totalSamples) {
    int frames = totalSamples / 2; // stereo interleaved
    if (frames <= 0)
      return;

    // convert incoming stereo frames to mono and append to circular buffer
    for (int i = 0; i < frames; ++i) {
      float sample = (buffer[2 * i] + buffer[2 * i + 1]) * 0.5f;
      mono[writePos++] = sample;
      if (writePos >= n) {
        // perform FFT on full buffer
        performFFT();
        writePos = 0;
      }
    }
  }

private:
  void performFFT() {
    // 1. Apply Hann Window
    vDSP_vmul(mono.data(), 1, window.data(), 1, mono.data(), 1, n);

    // 2. Prepare the Complex Buffer
    DSPSplitComplex complexBuffer;
    complexBuffer.realp = real.data();
    complexBuffer.imagp = imag.data();
    vDSP_ctoz((DSPComplex *)mono.data(), 2, &complexBuffer, 1, nOver2);

    // 3. FFT!
    vDSP_fft_zrip(fftSetup, &complexBuffer, 1, log2n, FFT_FORWARD);

    // 4. Magnitudes
    vDSP_zvmags(&complexBuffer, 1, fftMags.data(), 1, nOver2);

    // 5. Group into bands using vDSP (Hardware Accelerated)
    float raw[4] = {0, 0, 0, 0};

    // Highly optimized lambda using Accelerate
    auto calculateBandPeak = [&](int startBin, int endBin) {
      float maxSquaredAmp = 0;
      vDSP_Length length = endBin - startBin + 1;

      // Scan the array slice and find the maximum squared value instantly
      vDSP_maxv(&fftMags[startBin], 1, &maxSquaredAmp, length);

      // Do the expensive square root operation ONLY ONCE per band
      return sqrtf(maxSquaredAmp);
    };

    raw[0] = calculateBandPeak(1, 5);
    raw[1] = calculateBandPeak(6, 42);
    raw[2] = calculateBandPeak(43, 128);
    raw[3] = calculateBandPeak(129, 426);

    // 6. Apply smoothing & gain
    float decayRates[4] = {0.60f, 0.60f, 0.60f, 0.60f};
    float gains[4] = {0.005f, 0.01f, 0.03f, 0.06f};

    for (int i = 0; i < 4; ++i) {
      float value = raw[i] * gains[i];
      prevMagnitudes[i] =
          prevMagnitudes[i] * decayRates[i] + value * (1.0f - decayRates[i]);
      magnitudes[i] = prevMagnitudes[i];
    }
  }
};

#endif /* Processor_hpp */