#version 450
// Test triangle with vertex data (Tests\Test Vulkan): position, colour, UV,
// per-instance object ID.
// Variants (Shader Compile.bat): -DVG_DOUBLE for a double view-projection.
#ifdef VG_DOUBLE
#extension GL_ARB_gpu_shader_fp64 : require
layout(set = 0, binding = 0, std140) uniform ViewProjection { dmat4 matrix; } vp;
#else
layout(set = 0, binding = 0, std140) uniform ViewProjection { mat4 matrix; } vp;
#endif

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec2 inTexCoord;
layout(location = 3) in uvec2 inObjID;     // per instance

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec2 fragTexCoord;
layout(location = 2) flat out uvec2 fragObjectID;

void main()
{
#ifdef VG_DOUBLE
    gl_Position = vec4(vp.matrix * dvec4(inPosition, 1.0));
#else
    gl_Position = vp.matrix * vec4(inPosition, 1.0);
#endif
    fragColor    = inColor;
    fragTexCoord = inTexCoord;
    fragObjectID = inObjID;
}
