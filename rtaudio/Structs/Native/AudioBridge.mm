//
//  AudioBridge.mm
//  rtaudio
//
//  Created by zeph on 10/03/26.
//


#import "AudioBridge.h"
#import "AudioProcessor.hpp"

@implementation AudioBridge {
    AudioProcessor *processor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        processor = new AudioProcessor();
    }
    return self;
}

- (void)processBuffer:(const float *)buffer count:(int)count {
    processor->process(buffer, count);
}

- (simd_float4)getSmoothedMagnitudes {
    // Calls getBand() which does memory_order_relaxed atomic loads —
    // no heap allocation, safe to call from the render thread
    return simd_make_float4(
        processor->getBand(0),
        processor->getBand(1),
        processor->getBand(2),
        processor->getBand(3)
    );
}

- (void)dealloc {
    delete processor;
}

@end
