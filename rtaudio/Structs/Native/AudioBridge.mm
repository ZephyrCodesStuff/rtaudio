//
//  AudioBridge.mm
//  rtaudio
//
//  Created by zeph on 10/03/26.
//


#import "AudioBridge.h"
#import "AudioProcessor.hpp"

@implementation AudioBridge {
    AudioProcessor *processor; // Internal C++ instance
}

- (instancetype)init {
    self = [super init];
    if (self) {
        processor = new AudioProcessor();
    }
    return self;
}

- (void)processBuffer:(float *)buffer count:(int)count {
    processor->process(buffer, count);
}

- (simd_float4)getMagnitudes {
    // This creates a vector directly in memory/registers. Zero heap allocation.
    return simd_make_float4(processor->magnitudes[0],
                            processor->magnitudes[1],
                            processor->magnitudes[2],
                            processor->magnitudes[3]);
}

- (void)dealloc {
    delete processor;
}
@end
