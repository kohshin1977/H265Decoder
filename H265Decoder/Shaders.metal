//
//  Shaders.metal
//  H265Decoder
//
//  Created by 徳永功伸 on 2025/02/24.
//


#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader: outputs positions and texture coordinates for a full-screen quad.
vertex VertexOut vertexPassThrough(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Fragment shader: performs YUV (NV12) to RGB conversion.
fragment float4 nv12Fragment(VertexOut in [[stage_in]],
                             texture2d<float, access::sample> yTexture [[texture(0)]],
                             texture2d<float, access::sample> uvTexture [[texture(1)]],
                             sampler samp [[sampler(0)]]) {
    float y = yTexture.sample(samp, in.texCoord).r;
    float2 uv = uvTexture.sample(samp, in.texCoord).rg;
    
    // BT.601 conversion coefficients.
    float3 rgb;
    rgb.r = y + 1.402 * (uv.y - 0.5);
    rgb.g = y - 0.344136 * (uv.x - 0.5) - 0.714136 * (uv.y - 0.5);
    rgb.b = y + 1.772 * (uv.x - 0.5);
    
    return float4(rgb, 1.0);
}
