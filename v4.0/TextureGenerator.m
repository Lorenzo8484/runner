#import "TextureGenerator.h"

// High-quality procedural PBR texture generator
// Uses multi-octave noise and mathematical functions to create
// realistic-looking albedo, normal, roughness, metallic, AO maps

@implementation TextureGenerator

// ─── Perlin-like noise helpers ───
static inline float hash(float x, float y) {
    return fmodf(sinf(x * 127.1f + y * 311.7f) * 43758.5453f, 1.0f);
}

static inline float smoothNoise(float x, float y) {
    int ix = (int)floorf(x), iy = (int)floorf(y);
    float fx = x - ix, fy = y - iy;
    float sx = fx * fx * (3.0f - 2.0f * fx);
    float sy = fy * fy * (3.0f - 2.0f * fy);
    float n00 = hash(ix, iy), n10 = hash(ix+1, iy);
    float n01 = hash(ix, iy+1), n11 = hash(ix+1, iy+1);
    float nx0 = n00 + (n10 - n00) * sx;
    float nx1 = n01 + (n11 - n01) * sx;
    return nx0 + (nx1 - nx0) * sy;
}

static float fbm(float x, float y, int octaves) {
    float val = 0, amp = 0.5f, freq = 1.0f;
    for (int i = 0; i < octaves; i++) {
        val += amp * smoothNoise(x * freq, y * freq);
        amp *= 0.5f;
        freq *= 2.0f;
    }
    return val;
}

static UIImage *genImage(int size, float(^block)(int, int)) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = size * 4;
    uint8_t *data = (uint8_t *)malloc(size * bytesPerRow);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            float v = block(x, y);
            uint8_t b = (uint8_t)(v * 255);
            int idx = (y * size + x) * 4;
            data[idx] = b; data[idx+1] = b; data[idx+2] = b; data[idx+3] = 255;
        }
    }
    CGContextRef ctx = CGBitmapContextCreate(data, size, size, 8, bytesPerRow, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:img];
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(data);
    return ui;
}

// Generate full RGBA color image
static UIImage *genColorImage(int size, void(^block)(int, int, float*)) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = size * 4;
    uint8_t *data = (uint8_t *)malloc(size * bytesPerRow);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            float c[3]; block(x, y, c);
            int idx = (y * size + x) * 4;
            data[idx] = (uint8_t)(c[0]*255);
            data[idx+1] = (uint8_t)(c[1]*255);
            data[idx+2] = (uint8_t)(c[2]*255);
            data[idx+3] = 255;
        }
    }
    CGContextRef ctx = CGBitmapContextCreate(data, size, size, 8, bytesPerRow, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:img];
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(data);
    return ui;
}

// ─── GROUND: Dark earth with stones and roots ───
+ (SCNMaterialProperty *)pbrGroundMaterial {
    int S = 2048;
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    // Base color: brown earth with subtle variation
    mat.diffuse.contents = genColorImage(S, ^(int x, int y, float *c) {
        float fx = x / (float)S, fy = y / (float)S;
        float n = fbm(fx * 8, fy * 8, 5);
        float n2 = fbm(fx * 24, fy * 24, 3);
        c[0] = 0.25f + n * 0.15f + n2 * 0.05f;  // R
        c[1] = 0.15f + n * 0.10f + n2 * 0.03f;  // G
        c[2] = 0.08f + n * 0.06f;               // B
    });
    
    // Roughness: varied, rougher in dirt patches
    mat.roughness.contents = genImage(S, ^float(int x, int y) {
        float n = fbm(x/(float)S*12, y/(float)S*12, 5);
        return 0.6f + n * 0.35f;
    });
    
    // Metalness: dirt is non-metallic
    mat.metalness.contents = genImage(S, ^float(int x, int y) {
        return 0.0f;
    });
    
    // Normal: subtle terrain bumps
    mat.normal.contents = genColorImage(S, ^(int x, int y, float *c) {
        float dx = fbm((x+1)/(float)S*16, y/(float)S*16, 4) - fbm((x-1)/(float)S*16, y/(float)S*16, 4);
        float dy = fbm(x/(float)S*16, (y+1)/(float)S*16, 4) - fbm(x/(float)S*16, (y-1)/(float)S*16, 4);
        c[0] = 0.5f + dx * 2.0f;
        c[1] = 0.5f + dy * 2.0f;
        c[2] = 1.0f;
    });
    
    mat.diffuse.wrapS = SCNWrapModeRepeat;
    mat.diffuse.wrapT = SCNWrapModeRepeat;
    mat.roughness.wrapS = SCNWrapModeRepeat;
    mat.roughness.wrapT = SCNWrapModeRepeat;
    mat.normal.wrapS = SCNWrapModeRepeat;
    mat.normal.wrapT = SCNWrapModeRepeat;
    
    SCNMaterialProperty *prop = [SCNMaterialProperty materialPropertyWithContents:mat];
    return prop;
}

// ─── WOOD BARK: Brown with vertical grain ───
+ (SCNMaterialProperty *)pbrWoodMaterial {
    int S = 2048;
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    mat.diffuse.contents = genColorImage(S, ^(int x, int y, float *c) {
        float fx = x / (float)S, fy = y / (float)S;
        float grain = fbm(fx * 3, fy * 30, 4);  // vertical grain
        float detail = fbm(fx * 20, fy * 60, 3);
        float bark = grain * 0.4f + detail * 0.15f;
        c[0] = 0.35f + bark * 0.30f;
        c[1] = 0.18f + bark * 0.15f;
        c[2] = 0.08f + bark * 0.10f;
    });
    
    mat.roughness.contents = genImage(S, ^float(int x, int y) {
        float grain = fbm(x/(float)S*3, y/(float)S*30, 4);
        return 0.5f + grain * 0.4f;
    });
    
    mat.metalness.contents = genImage(S, ^float(int x, int y) {
        return 0.0f;
    });
    
    mat.normal.contents = genColorImage(S, ^(int x, int y, float *c) {
        float grain = fbm(x/(float)S*5, y/(float)S*20, 4);
        c[0] = 0.5f + grain * 1.5f;
        c[1] = 0.5f;
        c[2] = 1.0f;
    });
    
    [mat.diffuse setValue:@(SCNWrapModeRepeat) forKey:@"wrapS"];
    [mat.diffuse setValue:@(SCNWrapModeRepeat) forKey:@"wrapT"];
    
    return [SCNMaterialProperty materialPropertyWithContents:mat];
}

// ─── ROCK: Grey with sharp detail ───
+ (SCNMaterialProperty *)pbrRockMaterial {
    int S = 2048;
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    mat.diffuse.contents = genColorImage(S, ^(int x, int y, float *c) {
        float fx = x / (float)S, fy = y / (float)S;
        float n = fbm(fx * 10, fy * 10, 6);
        float cracks = fbm(fx * 30, fy * 30, 3);
        float grey = 0.35f + n * 0.25f;
        // Darker cracks
        if (cracks < 0.35f) grey -= 0.15f;
        c[0] = grey; c[1] = grey; c[2] = grey * 0.95f;
    });
    
    mat.roughness.contents = genImage(S, ^float(int x, int y) {
        float n = fbm(x/(float)S*8, y/(float)S*8, 5);
        return 0.55f + n * 0.35f;
    });
    
    mat.metalness.contents = genImage(S, ^float(int x, int y) {
        float n = fbm(x/(float)S*6, y/(float)S*6, 3);
        return n * 0.08f;  // slightly metallic in spots
    });
    
    mat.normal.contents = genColorImage(S, ^(int x, int y, float *c) {
        float dx = fbm((x+2)/(float)S*12, y/(float)S*12, 5) - fbm(x/(float)S*12, y/(float)S*12, 5);
        float dy = fbm(x/(float)S*12, (y+2)/(float)S*12, 5) - fbm(x/(float)S*12, y/(float)S*12, 5);
        c[0] = 0.5f + dx * 3.0f;
        c[1] = 0.5f + dy * 3.0f;
        c[2] = 1.0f;
    });
    
    return [SCNMaterialProperty materialPropertyWithContents:mat];
}

// ─── METAL: Polished gold for coins ───
+ (SCNMaterialProperty *)pbrMetalMaterial {
    int S = 1024;
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    mat.diffuse.contents = genColorImage(S, ^(int x, int y, float *c) {
        float fx = x / (float)S, fy = y / (float)S;
        float n = fbm(fx * 16, fy * 16, 4);
        float edge = (fx < 0.05f || fx > 0.95f || fy < 0.05f || fy > 0.95f) ? 0.7f : 1.0f;
        c[0] = 0.95f + n * 0.05f;
        c[1] = 0.72f + n * 0.08f;
        c[2] = 0.15f + n * 0.05f;
        c[0] *= edge; c[1] *= edge; c[2] *= edge;
    });
    
    mat.roughness.contents = genImage(S, ^float(int x, int y) {
        float n = fbm(x/(float)S*8, y/(float)S*8, 3);
        return 0.15f + n * 0.10f;  // polished
    });
    
    mat.metalness.contents = genImage(S, ^float(int x, int y) {
        return 1.0f;  // fully metallic
    });
    
    return [SCNMaterialProperty materialPropertyWithContents:mat];
}

// ─── FOLIAGE: Rich green leaves ───
+ (SCNMaterialProperty *)pbrFoliageMaterial {
    int S = 2048;
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    mat.diffuse.contents = genColorImage(S, ^(int x, int y, float *c) {
        float fx = x / (float)S, fy = y / (float)S;
        float n = fbm(fx * 10, fy * 10, 5);
        float veins = fbm(fx * 40, fy * 10, 3);
        c[0] = 0.05f + n * 0.12f;
        c[1] = 0.25f + n * 0.35f + veins * 0.08f;
        c[2] = 0.05f + n * 0.10f;
    });
    
    mat.roughness.contents = genImage(S, ^float(int x, int y) {
        return 0.7f + fbm(x/(float)S*8, y/(float)S*8, 3) * 0.25f;
    });
    
    mat.metalness.contents = genImage(S, ^float(int x, int y) {
        return 0.0f;
    });
    
    // Foliage normal with subsurface approximation
    mat.normal.contents = genColorImage(S, ^(int x, int y, float *c) {
        float dx = fbm((x+2)/(float)S*14, y/(float)S*14, 4) - fbm(x/(float)S*14, y/(float)S*14, 4);
        float dy = fbm(x/(float)S*14, (y+2)/(float)S*14, 4) - fbm(x/(float)S*14, y/(float)S*14, 4);
        c[0] = 0.5f + dx * 1.5f;
        c[1] = 0.5f + dy * 1.5f;
        c[2] = 1.0f;
    });
    
    return [SCNMaterialProperty materialPropertyWithContents:mat];
}

@end
