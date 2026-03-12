//
//  AudioBridge.m
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

- (NSArray<NSNumber *> *)getMagnitudes {
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        [result addObject:@(processor->magnitudes[i])];
    }
    return result;
}

- (void)dealloc {
    delete processor;
}
@end
