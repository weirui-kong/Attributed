// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

// Glyph tiles are scaled around their center and blurred by sampling a 9x9
// grid spread over three sigma; the mip level prefilters what the grid skips.

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    packed_float2 position;
    packed_float2 uv;
    float alpha;
    float sigma;
};

struct Fragment {
    float4 position [[position]];
    float2 uv;
    float alpha;
    float sigma;
};

vertex Fragment atrNumericTextVertex(uint id [[vertex_id]], const device Vertex *vertices [[buffer(0)]]) {
    Vertex input = vertices[id];
    Fragment output;
    output.position = float4(float2(input.position), 0, 1);
    output.uv = float2(input.uv);
    output.alpha = input.alpha;
    output.sigma = input.sigma;
    return output;
}

fragment float4 atrNumericTextFragment(Fragment input [[stage_in]], texture2d<float> tile [[texture(0)]], sampler tileSampler [[sampler(0)]]) {
    float inside = float(all(input.uv >= 0.0) && all(input.uv <= 1.0));
    float4 color = tile.sample(tileSampler, input.uv, level(0)) * inside;

    if (input.sigma >= 0.3) {
        float2 texel = 1.0 / float2(tile.get_width(), tile.get_height());
        float spacing = input.sigma * 0.75;
        float lod = max(0.0, log2(spacing) - 1.0);
        float total = 0;
        color = float4(0);

        for (int y = -4; y <= 4; y++) {
            for (int x = -4; x <= 4; x++) {
                float weight = exp(-float(x * x + y * y) * 0.28125);
                float2 uv = input.uv + float2(x, y) * spacing * texel;
                float within = float(all(uv >= 0.0) && all(uv <= 1.0));
                color += weight * within * tile.sample(tileSampler, uv, level(lod));
                total += weight;
            }
        }

        color /= total;
    }

    return color * input.alpha;
}
