//
//  WaveformShaders.metal
//  rtaudio
//
//  Created by zeph on 11/03/26.
//

#include <metal_stdlib>
using namespace metal;

// WARN: this must match the Swift counterpart!
struct WaveformParams {
    float magnitudes[4];
    float2 viewportSize;
    float backingScaleFactor;
    float3 colorTop;
    float3 colorBottom;
};

// Data passed from Vertex to Fragment
struct RasterizerData {
    float4 position [[position]];
    float2 uv;
};

// Generates a full-screen quad from 4 points
vertex RasterizerData waveform_vertex(uint vertexID [[vertex_id]]) {
    RasterizerData out;
    
    // Triangle strip covering the whole screen
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5; // Map to 0.0 -> 1.0
    
    return out;
}

// SDF for a capsule/rounded box
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + float2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Processes the pixels
fragment float4 waveform_fragment(RasterizerData in [[stage_in]],
                                  constant WaveformParams &params [[buffer(0)]]) {
    
    // Get the current pixel's exact X,Y coordinates
    float2 pixelCoord = in.uv * params.viewportSize;
    
    // Core Graphics has Y=0 at the top, Metal has Y=0 at the bottom. Flip it.
    pixelCoord.y = params.viewportSize.y - pixelCoord.y;
    
    float barWidth = 6.0 / params.backingScaleFactor;
    float spacing = 8.0 / params.backingScaleFactor;
    float totalWidth = 4.0 * barWidth + 3.0 * spacing;
    float startX = (params.viewportSize.x - totalWidth) / 2.0;
    
    float4 finalColor = float4(0.0); // Transparent background
    
    for (int i = 0; i < 4; i++) {
        float rawValue = params.magnitudes[i];
        float height = min(rawValue * 50.0 / params.backingScaleFactor + 5.0 / params.backingScaleFactor, 160.0 / params.backingScaleFactor);
        
        // Find the center of _this_ specific bar
        float centerX = startX + float(i) * (barWidth + spacing) + (barWidth / 2.0);
        float centerY = params.viewportSize.y / 2.0;
        
        // Calculate the distance from this pixel to the bar
        float2 p = pixelCoord - float2(centerX, centerY);
        float2 b = float2(barWidth / 2.0, height / 2.0);
        float r = barWidth / 2.0; // Corner radius is half width (Capsule)
        
        float d = sdRoundedBox(p, b, r);
        
        // If distance < 0, pixel is inside the bar: color it.
        float alpha = smoothstep(0.75, -0.75, d);
        
        float gradientFactor = in.uv.y;
        float3 mixedColor = mix(params.colorBottom, params.colorTop, gradientFactor);

        // Apply the gradient to the bars
        if (alpha > 0.0 && finalColor.a == 0.0) {
            finalColor = float4(mixedColor, alpha);
        }
    }
    
    return finalColor;
}
