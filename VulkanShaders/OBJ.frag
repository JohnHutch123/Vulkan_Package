#version 450
// Unlit diffuse display only. MTL lighting properties remain CPU scene data.
layout(early_fragment_tests) in;
layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;
layout(location = 2) flat in uvec2 objectID;
layout(location = 0) out vec4 outColor;
#ifdef OBJ_TEXTURE
layout(set = 1, binding = 0) uniform sampler2D diffuseMap;
layout(constant_id = 3) const float UV_SCALE_U = 1.0;
layout(constant_id = 4) const float UV_SCALE_V = 1.0;
layout(constant_id = 5) const float UV_OFFSET_U = 0.0;
layout(constant_id = 6) const float UV_OFFSET_V = 0.0;
layout(constant_id = 7) const float MAP_BRIGHTNESS = 0.0;
layout(constant_id = 8) const float MAP_CONTRAST = 1.0;
#endif
#ifdef OBJ_PICK
layout(set = 0, binding = 1, std430) buffer ObjectIDs { uvec2 values[]; } ids;
layout(push_constant) uniform ScreenSize { uvec2 size; } screen;
#endif
#ifdef OBJ_PICK_IMAGE
layout(set = 0, binding = 1, rg32ui) uniform uimage2D ids;
#endif
void main() {
    outColor = color;
#ifdef OBJ_TEXTURE
    vec2 mappedUV = uv * vec2(UV_SCALE_U, UV_SCALE_V) + vec2(UV_OFFSET_U, UV_OFFSET_V);
    mappedUV.y = 1.0 - mappedUV.y;
    vec4 texel = texture(diffuseMap, mappedUV);
    texel.rgb = vec3(MAP_BRIGHTNESS) + MAP_CONTRAST * texel.rgb;
    outColor *= texel;
#endif
#ifdef OBJ_PICK
    uvec2 pixel = uvec2(gl_FragCoord.xy);
    if (all(lessThan(pixel, screen.size)))
        ids.values[pixel.y * screen.size.x + pixel.x] = objectID;
#endif
#ifdef OBJ_PICK_IMAGE
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (all(lessThan(pixel, imageSize(ids))))
        imageStore(ids, pixel, uvec4(objectID, 0, 0));
#endif
}
