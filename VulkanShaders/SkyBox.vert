#version 450
// Sky (Vulkan_SkyBox.pas): one triangle covering the screen, at the far plane.
// The fragment shader turns each pixel into a world direction from the
// view-projection's 3x3 part alone, so the sky is at infinity: it has no
// size, no position, and encloses a scene of any extent.
// Variants (Shader Compile.bat): -DVG_DOUBLE for a double view-projection.
#ifdef VG_DOUBLE
#extension GL_ARB_gpu_shader_fp64 : require
layout(set = 0, binding = 0, std140) uniform ViewProjection { dmat4 matrix; } vp;
#else
layout(set = 0, binding = 0, std140) uniform ViewProjection { mat4 matrix; } vp;
#endif

// The store's vertex layout carries the sky's parameters: the same values in
// all three vertices (TvgSkyBox.WriteParams).
layout(location = 0) in vec3 inPosition;    // clip x, y and depth
layout(location = 1) in vec4 inColor;       // day factor, Z-up, sun visible, moon visible
layout(location = 2) in vec3 inNormal;      // direction to the sun  (east, up, north)
layout(location = 3) in vec3 inTangent;     // direction to the moon (east, up, north)
layout(location = 4) in vec3 inBiTangent;   // brightness, sun size (degrees), moon size (degrees)

layout(location = 0) out vec2 fragNDC;
layout(location = 1) flat out vec3 fragRow0;
layout(location = 2) flat out vec3 fragRow1;
layout(location = 3) flat out vec3 fragRow2;
layout(location = 4) flat out vec3 fragRow3;
layout(location = 5) flat out vec4 fragParams;
layout(location = 6) flat out vec3 fragSunDir;
layout(location = 7) flat out vec3 fragMoonDir;
layout(location = 8) flat out vec3 fragSizes;

void main()
{
    gl_Position = vec4(inPosition, 1.0);
    fragNDC     = inPosition.xy;

    // Rows of the 3x3 part: what the matrix does to a direction.  No
    // translation is involved, so float holds them whatever the world
    // coordinates are.
    mat4 m   = mat4(vp.matrix);
    fragRow0 = vec3(m[0][0], m[1][0], m[2][0]);
    fragRow1 = vec3(m[0][1], m[1][1], m[2][1]);
    fragRow2 = vec3(m[0][2], m[1][2], m[2][2]);
    fragRow3 = vec3(m[0][3], m[1][3], m[2][3]);

    fragParams  = inColor;
    fragSunDir  = inNormal;
    fragMoonDir = inTangent;
    fragSizes   = inBiTangent;
}
