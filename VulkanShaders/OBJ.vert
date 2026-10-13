#version 450
// Public OBJ loader layout: position, colour, normal, UV, tangent, bitangent,
// per-instance ID.  The normal and tangent frame are retained for lighting
// and normal maps; this unlit shader does not use them yet.
// Variants (Shader Compile.bat): -DVG_DOUBLE for a double view-projection;
// -DVG_INSTANCED for a store whose instances also carry idtMatrix (OBJInst*).
#ifdef VG_DOUBLE
#extension GL_ARB_gpu_shader_fp64 : require
layout(set = 0, binding = 0, std140) uniform ViewProjection { dmat4 matrix; } vp;
#else
layout(set = 0, binding = 0, std140) uniform ViewProjection { mat4 matrix; } vp;
#endif
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec2 inUV;
layout(location = 4) in vec3 inTangent;     // along +U, unit, perpendicular to the normal
layout(location = 5) in vec3 inBiTangent;   // along +V (normal x tangent, mirrored with the UVs)
layout(location = 6) in uvec2 inObjectID;
#ifdef VG_INSTANCED
layout(location = 7) in mat4 inInstanceMatrix;   // per instance, locations 7..10
#endif
layout(location = 0) out vec4 color;
layout(location = 1) out vec2 uv;
layout(location = 2) flat out uvec2 objectID;
void main() {
#ifdef VG_INSTANCED
    vec4 position = inInstanceMatrix * vec4(inPosition, 1.0);
#else
    vec4 position = vec4(inPosition, 1.0);
#endif
#ifdef VG_DOUBLE
    gl_Position = vec4(vp.matrix * dvec4(position));
#else
    gl_Position = vp.matrix * position;
#endif
    gl_PointSize = 1.0;
    color = inColor;
    uv = inUV;
    objectID = inObjectID;
}
