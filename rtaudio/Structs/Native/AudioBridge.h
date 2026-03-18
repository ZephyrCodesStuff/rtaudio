//
//  AudioBridge.h
//  rtaudio
//
//  Created by zeph on 10/03/26.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioBridge : NSObject

- (void)processBuffer:(const float *)buffer count:(int)count;

// Reads atomically from the processor — safe to call from any thread
- (simd_float4)getSmoothedMagnitudes;

@end

NS_ASSUME_NONNULL_END
