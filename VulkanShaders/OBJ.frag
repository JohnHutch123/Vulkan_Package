#version 450
// Diffuse colour/map under a two-sided headlight, or unlit.  MTL lighting
// properties remain CPU scene data.
// Variants (Shader Compile.bat): -DOBJ_TEXTURE diffuse map; -DVG_PICK storage-
// buffer picking, -DVG_PICK_IMAGE image picking, neither for no picking.
layout(early_fragment_tests) in;
layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;
layout(location = 2) flat in uvec2 objectID;
layout(location = 3) in vec3 normal;
layout(location = 4) in vec3 modelPosition;
layout(location = 5) in vec3 lightDir;
layout(location = 0) out vec4 outColor;
// TvgOBJShading: 0 unlit, 1 flat (each triangle's own plane, from the
// position's screen derivatives), 2 smooth (the interpolated vertex normal).
layout(constant_id = 9) const int SHADING = 0;
// Brightness of a surface seen edge-on; face-on it is 1.
layout(constant_id = 10) const float AMBIENT = 0.35;
#ifdef OBJ_TEXTURE
layout(set = 1, binding = 0) uniform sampler2D diffuseMap;
layout(constant_id = 3) const float UV_SCALE_U = 1.0;
layout(constant_id = 4) const float UV_SCALE_V = 1.0;
layout(constant_id = 5) const float UV_OFFSET_U = 0.0;
layout(constant_id = 6) const float UV_OFFSET_V = 0.0;
layout(constant_id = 7) const float MAP_BRIGHTNESS = 0.0;
layout(constant_id = 8) const float MAP_CONTRAST = 1.0;
#endif
#ifdef VG_PICK
layout(set = 0, binding = 1, std430) buffer ObjectIDs { uvec2 values[]; } ids;
layout(push_constant) uniform ScreenSize { uvec2 size; } screen;
#endif
#ifdef VG_PICK_IMAGE
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
    if (SHADING != 0) {
        vec3 n = (SHADING == 1) ? cross(dFdx(modelPosition), dFdy(modelPosition)) : normal;
        float d = 1.0;   // nothing to light by: as unlit
        if (dot(n, n) > 0.0 && dot(lightDir, lightDir) > 0.0)
            d = abs(dot(normalize(n), normalize(lightDir)));
        outColor.rgb *= AMBIENT + (1.0 - AMBIENT) * d;
    }
#ifdef VG_PICK
    uvec2 pixel = uvec2(gl_FragCoord.xy);
    if (all(lessThan(pixel, screen.size)))
        ids.values[pixel.y * screen.size.x + pixel.x] = objectID;
#endif
#ifdef VG_PICK_IMAGE
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (all(lessThan(pixel, imageSize(ids))))
        imageStore(ids, pixel, uvec4(objectID, 0, 0));
#endif
}
