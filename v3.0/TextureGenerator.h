#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

// Generates 4K×4K PBR texture maps procedurally
// Maps: baseColor, normal, roughness, metallic, ambientOcclusion
@interface TextureGenerator : NSObject

+ (SCNMaterialProperty *)pbrGroundMaterial;
+ (SCNMaterialProperty *)pbrWoodMaterial;
+ (SCNMaterialProperty *)pbrRockMaterial;
+ (SCNMaterialProperty *)pbrMetalMaterial;
+ (SCNMaterialProperty *)pbrFoliageMaterial;

@end
