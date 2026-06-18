#import <SceneKit/SceneKit.h>

@interface ParticleSystem : NSObject

+ (SCNParticleSystem *)dustTrail;
+ (SCNParticleSystem *)impactDirt;
+ (SCNParticleSystem *)coinBurst;
+ (SCNParticleSystem *)leavesRustle;

@end
