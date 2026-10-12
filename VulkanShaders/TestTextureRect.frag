#version 450
// Textured test geometry (Tests\Test Vulkan): the store's texture.
// Variants (Shader Compile.bat): -DVG_PICK storage-buffer picking,
// -DVG_PICK_IMAGE image picking, neither for no picking.

// object IDs are written only after the depth test passes
layout(early_fragment_tests) in;

layout(set = 1, binding = 0) uniform sampler2D SimpleTexture;

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec2 fragTexCoord;
layout(location = 2) flat in uvec2 fragObjectID;

layout(location = 0) out vec4 outColor;

#ifdef VG_PICK
layout(constant_id = 0) const bool USE_OBJECTID = true;
layout(set = 0, binding = 1, std430) buffer ObjectIDs { uvec2 values[]; } ids;
layout(push_constant) uniform ScreenSize { uvec2 size; } screen;
#endif
#ifdef VG_PICK_IMAGE
layout(set = 0, binding = 1, rg32ui) uniform uimage2D ids;
#endif

void main()
{
    outColor = texture(SimpleTexture, fragTexCoord);

#ifdef VG_PICK
    uvec2 pixel = uvec2(gl_FragCoord.xy);
    if (USE_OBJECTID && all(lessThan(pixel, screen.size)))
        ids.values[pixel.y * screen.size.x + pixel.x] = fragObjectID;
#endif
#ifdef VG_PICK_IMAGE
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (all(lessThan(pixel, imageSize(ids))))
        imageStore(ids, pixel, uvec4(fragObjectID, 0, 0));
#endif
}
