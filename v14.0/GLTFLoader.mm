#import "GLTFLoader.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

@implementation GLTFLoader

+ (SCNNode *)loadModel:(NSString *)name {
    // Try multiple paths
    NSString *path = nil;
    NSBundle *bundle = [NSBundle mainBundle];
    
    path = [bundle pathForResource:[@"Assets/models/player/" stringByAppendingString:name] ofType:@"glb"];
    if (!path) path = [bundle pathForResource:[@"Assets/models/trees/" stringByAppendingString:name] ofType:@"glb"];
    if (!path) path = [bundle pathForResource:[@"Assets/models/rocks/" stringByAppendingString:name] ofType:@"glb"];
    if (!path) path = [bundle pathForResource:[@"Assets/models/foliage/" stringByAppendingString:name] ofType:@"glb"];
    if (!path) path = [bundle pathForResource:[@"Assets/models/road/" stringByAppendingString:name] ofType:@"gltf"];
    if (!path) path = [bundle pathForResource:[@"Assets/models/player/" stringByAppendingString:name] ofType:nil];
    if (!path) path = [bundle pathForResource:[@"Assets/models/trees/" stringByAppendingString:name] ofType:nil];
    if (!path) path = [bundle pathForResource:[@"Assets/models/rocks/" stringByAppendingString:name] ofType:nil];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    
    cgltf_options opts = {};
    cgltf_data *data = NULL;
    cgltf_result res = cgltf_parse_file(&opts, [path UTF8String], &data);
    if (res != cgltf_result_success) return nil;
    
    res = cgltf_load_buffers(&opts, data, [path UTF8String]);
    if (res != cgltf_result_success) { cgltf_free(data); return nil; }
    
    SCNNode *rootNode = [SCNNode node];
    
    for (size_t mi = 0; mi < data->meshes_count; mi++) {
        cgltf_mesh *mesh = &data->meshes[mi];
        
        for (size_t pi = 0; pi < mesh->primitives_count; pi++) {
            cgltf_primitive *prim = &mesh->primitives[pi];
            
            SCNGeometrySource *posSrc = nil, *normSrc = nil, *uvSrc = nil;
            SCNGeometryElement *elem = nil;
            
            // ── Positions ──
            if (prim->attributes_count > 0) {
                cgltf_accessor *posAcc = prim->attributes[0].data;
                size_t vCount = posAcc->count;
                float *positions = (float *)malloc(vCount * 3 * sizeof(float));
                cgltf_accessor_unpack_floats(posAcc, positions, vCount * 3);
                NSData *posData = [NSData dataWithBytesNoCopy:positions length:vCount * 3 * sizeof(float) freeWhenDone:YES];
                posSrc = [SCNGeometrySource geometrySourceWithData:posData
                                                          semantic:SCNGeometrySourceSemanticVertex
                                                       vectorCount:vCount
                                                   floatComponents:YES
                                               componentsPerVector:3
                                                 bytesPerComponent:sizeof(float)
                                                        dataOffset:0
                                                        dataStride:3 * sizeof(float)];
            }
            
            // ── Normals ──
            for (size_t ai = 0; ai < prim->attributes_count; ai++) {
                if (strcmp(prim->attributes[ai].name, "NORMAL") == 0) {
                    cgltf_accessor *normAcc = prim->attributes[ai].data;
                    size_t nCount = normAcc->count;
                    float *normals = (float *)malloc(nCount * 3 * sizeof(float));
                    cgltf_accessor_unpack_floats(normAcc, normals, nCount * 3);
                    NSData *normData = [NSData dataWithBytesNoCopy:normals length:nCount * 3 * sizeof(float) freeWhenDone:YES];
                    normSrc = [SCNGeometrySource geometrySourceWithData:normData
                                                               semantic:SCNGeometrySourceSemanticNormal
                                                            vectorCount:nCount
                                                        floatComponents:YES
                                                    componentsPerVector:3
                                                      bytesPerComponent:sizeof(float)
                                                             dataOffset:0
                                                             dataStride:3 * sizeof(float)];
                    break;
                }
            }
            
            // ── TexCoords ──
            for (size_t ai = 0; ai < prim->attributes_count; ai++) {
                if (strcmp(prim->attributes[ai].name, "TEXCOORD_0") == 0) {
                    cgltf_accessor *uvAcc = prim->attributes[ai].data;
                    size_t uvCount = uvAcc->count;
                    float *uvs = (float *)malloc(uvCount * 2 * sizeof(float));
                    cgltf_accessor_unpack_floats(uvAcc, uvs, uvCount * 2);
                    NSData *uvData = [NSData dataWithBytesNoCopy:uvs length:uvCount * 2 * sizeof(float) freeWhenDone:YES];
                    uvSrc = [SCNGeometrySource geometrySourceWithData:uvData
                                                             semantic:SCNGeometrySourceSemanticTexcoord
                                                          vectorCount:uvCount
                                                      floatComponents:YES
                                                  componentsPerVector:2
                                                    bytesPerComponent:sizeof(float)
                                                           dataOffset:0
                                                           dataStride:2 * sizeof(float)];
                    break;
                }
            }
            
            // ── Indices ──
            if (prim->indices && posSrc) {
                cgltf_accessor *idxAcc = prim->indices;
                size_t idxCount = idxAcc->count;
                
                if (idxAcc->component_type == cgltf_component_type_r_16u) {
                    uint16_t *indices = (uint16_t *)malloc(idxCount * sizeof(uint16_t));
                    cgltf_accessor_unpack_indices(idxAcc, indices, sizeof(uint16_t), idxCount);
                    NSData *idxData = [NSData dataWithBytesNoCopy:indices length:idxCount * sizeof(uint16_t) freeWhenDone:YES];
                    elem = [SCNGeometryElement geometryElementWithData:idxData
                                                         primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                        primitiveCount:(int)(idxCount / 3)
                                                         bytesPerIndex:sizeof(uint16_t)];
                } else {
                    uint32_t *indices = (uint32_t *)malloc(idxCount * sizeof(uint32_t));
                    cgltf_accessor_unpack_indices(idxAcc, indices, sizeof(uint32_t), idxCount);
                    NSData *idxData = [NSData dataWithBytesNoCopy:indices length:idxCount * sizeof(uint32_t) freeWhenDone:YES];
                    elem = [SCNGeometryElement geometryElementWithData:idxData
                                                         primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                        primitiveCount:(int)(idxCount / 3)
                                                         bytesPerIndex:sizeof(uint32_t)];
                }
            }
            
            // ── Material ──
            SCNMaterial *mat = [SCNMaterial material];
            mat.lightingModelName = SCNLightingModelPhysicallyBased;
            
            // Default: extract from GLTF PBR material
            if (prim->material) {
                cgltf_material *cmat = prim->material;
                float *bc = cmat->pbr_metallic_roughness.base_color_factor;
                mat.diffuse.contents = [UIColor colorWithRed:bc[0] green:bc[1] blue:bc[2] alpha:bc[3]];
                mat.roughness.contents = @(cmat->pbr_metallic_roughness.roughness_factor);
                mat.metalness.contents = @(cmat->pbr_metallic_roughness.metallic_factor);
                
                // Load base color texture if present
                cgltf_texture *tex = cmat->pbr_metallic_roughness.base_color_texture.texture;
                if (tex && tex->image && tex->image->buffer_view) {
                    cgltf_buffer_view *bv = tex->image->buffer_view;
                    const uint8_t *imgData = ((const uint8_t*)bv->buffer->data) + bv->offset;
                    NSData *nsData = [NSData dataWithBytes:imgData length:bv->size];
                    UIImage *img = [UIImage imageWithData:nsData];
                    if (img) mat.diffuse.contents = img;
                }
            } else {
                // No GLTF material — use a neutral color with tint
                mat.diffuse.contents = [UIColor colorWithRed:0.6 green:0.55 blue:0.5 alpha:1.0];
                mat.roughness.contents = @0.7;
                mat.metalness.contents = @0.0;
            }
            
            // ── Create geometry ──
            if (posSrc) {
                NSMutableArray *sources = [NSMutableArray arrayWithObject:posSrc];
                if (normSrc) [sources addObject:normSrc];
                if (uvSrc) [sources addObject:uvSrc];
                
                if (!elem) {
                    // Fallback: non-indexed
                    int triCount = (int)(posSrc.vectorCount / 3);
                    elem = [SCNGeometryElement geometryElementWithData:nil
                                                         primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                        primitiveCount:MAX(1, triCount)
                                                         bytesPerIndex:0];
                }
                
                SCNGeometry *geo = [SCNGeometry geometryWithSources:sources elements:@[elem]];
                geo.materials = @[mat];
                
                // Copy node transform if present
                SCNNode *meshNode = [SCNNode nodeWithGeometry:geo];
                
                // Apply mesh node transform from GLTF
                if (mesh->weights_count > 0) {
                    // Morph targets — skip for simplicity
                }
                
                [rootNode addChildNode:meshNode];
            }
        }
        
        // ── Apply node hierarchy from GLTF ──
        for (size_t ni = 0; ni < data->nodes_count; ni++) {
            cgltf_node *node = &data->nodes[ni];
            if (node->mesh) {
                // Find the corresponding SCNNode we just created
                for (SCNNode *child in rootNode.childNodes) {
                    if (child.geometry) {
                        // Apply transform
                        if (node->has_matrix) {
                            simd_float4x4 m;
                            for (int r = 0; r < 4; r++)
                                for (int c = 0; c < 4; c++)
                                    m.columns[c][r] = node->matrix[r * 4 + c];
                            child.simdTransform = m;
                        } else {
                            if (node->has_translation)
                                child.position = SCNVector3Make(node->translation[0], node->translation[1], node->translation[2]);
                            if (node->has_rotation)
                                child.orientation = SCNVector4Make(node->rotation[0], node->rotation[1], node->rotation[2], node->rotation[3]);
                            if (node->has_scale)
                                child.scale = SCNVector3Make(node->scale[0], node->scale[1], node->scale[2]);
                        }
                        break;
                    }
                }
            }
        }
    }
    
    // Normalize the model — center and scale
    SCNVector3 min = SCNVector3Make(INFINITY, INFINITY, INFINITY);
    SCNVector3 max = SCNVector3Make(-INFINITY, -INFINITY, -INFINITY);
    [self getBoundingBox:rootNode min:&min max:&max];
    
    float sizeX = max.x - min.x, sizeY = max.y - min.y, sizeZ = max.z - min.z;
    float maxDim = MAX(sizeX, MAX(sizeY, sizeZ));
    if (maxDim > 0.01) {
        float scale = 2.0 / maxDim;
        rootNode.scale = SCNVector3Make(scale, scale, scale);
        rootNode.position = SCNVector3Make(
            -(min.x + max.x) * 0.5 * scale,
            -min.y * scale,
            -(min.z + max.z) * 0.5 * scale
        );
    }
    
    cgltf_free(data);
    return rootNode;
}

+ (void)getBoundingBox:(SCNNode *)node min:(SCNVector3 *)min max:(SCNVector3 *)max {
    if (node.geometry) {
        SCNVector3 bmin, bmax;
        [node getBoundingBoxMin:&bmin max:&bmax];
        SCNVector3 worldMin = [node convertPosition:bmin toNode:nil];
        SCNVector3 worldMax = [node convertPosition:bmax toNode:nil];
        min->x = MIN(min->x, worldMin.x); min->y = MIN(min->y, worldMin.y); min->z = MIN(min->z, worldMin.z);
        max->x = MAX(max->x, worldMax.x); max->y = MAX(max->y, worldMax.y); max->z = MAX(max->z, worldMax.z);
    }
    for (SCNNode *child in node.childNodes) {
        [self getBoundingBox:child min:min max:max];
    }
}

+ (NSArray<SCNAnimation *> *)loadAnimations:(NSString *)name {
    return @[];
}

@end
