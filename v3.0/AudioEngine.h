#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioEngine : NSObject

+ (instancetype)shared;

- (void)startAmbient;
- (void)playFootstep;
- (void)playJump;
- (void)playSlide;
- (void)playCoin;
- (void)playHit;
- (void)playDeath;

@end
