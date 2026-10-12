#version 450
// Public OBJ loader layout: position, colour, normal, UV, per-instance ID.
// Compile with -DOBJ_DOUBLE=1 for the double view-projection variant.
#ifdef OBJ_DOUBLE
#extension GL_ARB_gpu_shader_fp64 : require
layout(set = 0, binding = 0, std140) uniform ViewProjection { dmat4 matrix; } vp;
#else
layout(set = 0, binding = 0, std140) uniform ViewProjection { mat4 matrix; } vp;
#endif
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec3 inNormal; // retained for future lighting
layout(location = 3) in vec2 inUV;
layout(location = 4) in uvec2 inObjectID;
layout(location = 0) out vec4 color;
layout(location = 1) out vec2 uv;
layout(location = 2) flat out uvec2 objectID;
void main() {
#ifdef OBJ_DOUBLE
    gl_Position = vec4(vp.matrix * dvec4(inPosition, 1.0));
#else
    gl_Position = vp.matrix * vec4(inPosition, 1.0);
#endif
    gl_PointSize = 1.0;
    color = inColor;
    uv = inUV;
    objectID = inObjectID;
}
