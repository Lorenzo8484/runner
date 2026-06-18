#import <SceneKit/SceneKit.h>

/// Loads GLB files into SCNNode using cgltf
@interface GLTFLoader : NSObject

/// Load a static GLB model from the app bundle
+ (nullable SCNNode *)loadModel:(NSString *)name;

/// Load and extract all animation clips from a GLB
+ (nullable NSArray<SCNAnimation *> *)loadAnimations:(NSString *)name;

@end
