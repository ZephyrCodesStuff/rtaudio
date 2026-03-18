#ifndef Processor_hpp
#define Processor_hpp

#include <Accelerate/Accelerate.h>
#include <atomic>
#include <cmath>

class AudioProcessor {
private:
    static constexpr int   kBlockSize = 512;   // lower latency than 1024
    static constexpr int   kBands     = 4;
    static constexpr float kAttack    = 0.85f; // fast rise
    static constexpr float kRelease   = 0.40f; // slower fall — more musical
    static constexpr float kGains[kBands] = {3.5f, 6.0f, 9.0f, 20.0f};

    float    sampleRate;
    int      writePos = 0;
    float    mono[kBlockSize]      = {};
    float    filtered[kBlockSize]  = {};

    vDSP_biquad_Setup setups[kBands];
    alignas(16) float delays[kBands][4] = {};

    float envelopes[kBands] = {};

    // Lock-free: audio thread writes, render thread reads
    // One atomic per band — fits in a cache line
    alignas(64) std::atomic<float> bandParams[kBands] = {};

public:
    explicit AudioProcessor(float sr = 48000.0f) : sampleRate(sr) {
        // Single biquad per band — just enough separation, minimal CPU
        setupBiquad(0, FilterType::LowPass,  250.0f,  0.707f);
        setupBiquad(1, FilterType::BandPass, 707.0f,  0.40f);
        setupBiquad(2, FilterType::BandPass, 3464.0f, 0.85f);
        setupBiquad(3, FilterType::HighPass, 6000.0f, 0.707f);
    }

    ~AudioProcessor() {
        for (int i = 0; i < kBands; ++i)
            vDSP_biquad_DestroySetup(setups[i]);
    }

    // Called by CoreAudio — must be real-time safe (no alloc, no locks)
    void process(const float* __restrict__ buffer, int totalSamples) {
        if (__builtin_expect(totalSamples <= 0, 0)) return;

        const float* src = buffer;
        int remaining = totalSamples;

        while (remaining > 0) {
            int toCopy = std::min(remaining, kBlockSize - writePos);
            memcpy(mono + writePos, src, toCopy * sizeof(float));
            writePos  += toCopy;
            src       += toCopy;
            remaining -= toCopy;

            if (writePos >= kBlockSize) {
                processBlock();
                writePos = 0;
            }
        }
    }

    // Called by render thread — lock-free read
    float getBand(int i) const {
        return bandParams[i].load(std::memory_order_relaxed);
    }

private:
    enum class FilterType { LowPass, BandPass, HighPass };

    void processBlock() {
        for (int i = 0; i < kBands; ++i) {
            vDSP_biquad(setups[i], delays[i], mono, 1, filtered, 1, kBlockSize);

            // RMS over the block — more stable than peak for driving animation
            float rms = 0.0f;
            vDSP_rmsqv(filtered, 1, &rms, kBlockSize);

            if (__builtin_expect(!std::isfinite(rms), 0)) rms = 0.0f;
            
            float boostedRms = rms * kGains[i];
            boostedRms = std::min(boostedRms, 1.0f);

            // Asymmetric envelope: attack fast, release slow
            float prev = envelopes[i];
            envelopes[i] = (boostedRms > prev)
                ? prev * (1.0f - kAttack)  + boostedRms * kAttack
                : prev * (1.0f - kRelease) + boostedRms * kRelease;

            bandParams[i].store(envelopes[i], std::memory_order_relaxed);
        }
    }

    void setupBiquad(int idx, FilterType type, float freq, float q) {
        const double w0    = 2.0 * M_PI * freq / sampleRate;
        const double sinw  = std::sin(w0);
        const double cosw  = std::cos(w0);
        const double alpha = sinw / (2.0 * q);

        double b0, b1, b2;
        const double a0 =  1.0 + alpha;
        const double a1 = -2.0 * cosw;
        const double a2 =  1.0 - alpha;

        switch (type) {
            case FilterType::LowPass:
                b0 = (1.0 - cosw) * 0.5; b1 = 1.0 - cosw; b2 = b0; break;
            case FilterType::HighPass:
                b0 = (1.0 + cosw) * 0.5; b1 = -(1.0 + cosw); b2 = b0; break;
            case FilterType::BandPass:
                b0 = alpha; b1 = 0.0; b2 = -alpha; break;
        }

        const double coeffs[5] = { b0/a0, b1/a0, b2/a0, a1/a0, a2/a0 };
        setups[idx] = vDSP_biquad_CreateSetup(coeffs, 1);
    }
};

#endif // !Processor_hpp
