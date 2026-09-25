#version 450
#extension GL_ARB_gpu_shader_fp64 : require

layout(set = 0, binding = 0, std140) uniform ViewProjBufferObject {
    dmat4 matrix;
} viewproj;
// Global Resource View/Projection matrix SHOULD BE ALWAYS SET = 0

//select layout at Set 2
layout(std140, set = 2, binding = 0) uniform IVec2UB {
    ivec2 value;
    // padding may follow here to meet std140 rules
} Selectbuf;

// Push constants block
layout(push_constant, std430) uniform constants {
    dmat4 render_matrix;
} PushConstants;

layout(location = 0) in vec3 inPosition; 
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inTexCoord;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 fragTexCoord;
layout(location = 2) flat out ivec2 selectXY;

void main() {
    dvec4 pos = ((viewproj.matrix * PushConstants.render_matrix)  * dvec4(inPosition, 1.0));
    gl_Position = vec4(pos);  
	
    fragColor = inColor;
    fragTexCoord = inTexCoord;
	
	selectXY = Selectbuf.value;
}