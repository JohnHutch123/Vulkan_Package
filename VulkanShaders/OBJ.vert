#version 450
// Public OBJ loader layout: position, colour, normal, UV, tangent, bitangent,
// per-instance ID.  The normal, model-space position and a headlight
// direction go to OBJ.frag for its SHADING modes; the tangent frame is
// retained for normal maps, not used yet.
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
// All in model space, before any instance matrix: model coordinates are
// usually small, so the flat-shading derivatives keep their precision even in
// a double-precision scene with large world coordinates.
layout(location = 3) out vec3 normal;
layout(location = 4) out vec3 modelPosition;
layout(location = 5) out vec3 lightDir;
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
    normal = inNormal;
    modelPosition = inPosition;
    // Headlight: along the view direction.  A perspective matrix's w row is
    // depth along it; an orthographic one's w row is (0 0 0 1), but its z row
    // is.  The fragment shader lights both sides, so the sign does not matter.
    mat4 m = mat4(vp.matrix);
    vec3 view = vec3(m[0][3], m[1][3], m[2][3]);
    if (dot(view, view) < 1e-20) view = vec3(m[0][2], m[1][2], m[2][2]);
#ifdef VG_INSTANCED
    // Into model space; exact for rotation and uniform scale.
    view = transpose(mat3(inInstanceMatrix)) * view;
#endif
    lightDir = view;
}
