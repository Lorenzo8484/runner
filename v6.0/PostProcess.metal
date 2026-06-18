#include <metal_stdlib>
using namespace metal;

// ─── ACES Filmic Tone Mapping ───
constant float3x3 ACESInputMat = float3x3(
    float3(0.59719, 0.35458, 0.04823),
    float3(0.07600, 0.90834, 0.01566),
    float3(0.02840, 0.13383, 0.83777)
);

constant float3x3 ACESOutputMat = float3x3(
    float3( 1.60475, -0.53108, -0.07367),
    float3(-0.10208,  1.10813, -0.00605),
    float3(-0.00327, -0.07276,  1.07602)
);

float3 RRTAndODTFit(float3 v) {
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

float3 ACESFitted(float3 color) {
    color = ACESInputMat * color;
    color = RRTAndODTFit(color);
    color = ACESOutputMat * color;
    return saturate(color);
}

// ─── Bloom pass: horizontal ───
kernel void bloom_horizontal(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]],
    constant float &threshold [[buffer(0)]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    
    float4 sum = 0;
    float totalWeight = 0;
    float weights[5] = {0.0545, 0.2442, 0.4026, 0.2442, 0.0545};
    int radius = 2;
    
    for (int x = -radius; x <= radius; x++) {
        int2 samplePos = int2(int(gid.x) + x, int(gid.y));
        samplePos.x = clamp(samplePos.x, 0, int(inTex.get_width()) - 1);
        float4 sample = inTex.read(uint2(samplePos));
        float brightness = dot(sample.rgb, float3(0.299, 0.587, 0.114));
        float weight = weights[x + radius] * step(threshold, brightness);
        sum += sample * weight;
        totalWeight += weight;
    }
    
    outTex.write(sum / max(totalWeight, 0.001), gid);
}

// ─── Bloom pass: vertical ───
kernel void bloom_vertical(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    
    float4 sum = 0;
    float weights[5] = {0.0545, 0.2442, 0.4026, 0.2442, 0.0545};
    int radius = 2;
    
    for (int y = -radius; y <= radius; y++) {
        int2 samplePos = int2(int(gid.x), int(gid.y) + y);
        samplePos.y = clamp(samplePos.y, 0, int(inTex.get_height()) - 1);
        sum += inTex.read(uint2(samplePos)) * weights[y + radius];
    }
    
    outTex.write(sum, gid);
}

// ─── Tone Mapping + Final Composite ───
kernel void tone_map(
    texture2d<float, access::read> sceneTex [[texture(0)]],
    texture2d<float, access::read> bloomTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    constant float &exposure [[buffer(0)]],
    constant float &bloomStrength [[buffer(1)]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    
    float4 scene = sceneTex.read(gid);
    float4 bloom = bloomTex.read(gid);
    
    // Combine
    float3 hdrColor = (scene.rgb * exposure) + (bloom.rgb * bloomStrength);
    
    // ACES tone mapping
    float3 mapped = ACESFitted(hdrColor);
    
    // Gamma correction (2.2)
    mapped = pow(mapped, float3(1.0/2.2));
    
    outTex.write(float4(mapped, scene.a), gid);
}

// ─── Vignette ───
kernel void vignette(
    texture2d<float, access::read> inTex [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]],
    constant float &intensity [[buffer(0)]])
{
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    
    float2 uv = float2(gid) / float2(outTex.get_width(), outTex.get_height());
    uv = uv * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv, uv) * intensity;
    vignette = saturate(vignette);
    
    float4 color = inTex.read(gid);
    color.rgb *= vignette;
    outTex.write(color, gid);
}
