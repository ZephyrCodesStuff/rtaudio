//
//  AudioBridge.h
//  rtaudio
//
//  Created by zeph on 10/03/26.
//


#import <Foundation/Foundation.h>

@interface AudioBridge : NSObject
- (void)processBuffer:(float *)buffer count:(int)count;
- (NSArray<NSNumber *> *)getMagnitudes;
@end
