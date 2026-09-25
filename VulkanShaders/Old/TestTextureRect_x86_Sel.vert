#version 450

layout(set = 0, binding = 0, std140) uniform ViewProjBufferObject {
    mat4 matrix;
} viewproj;
//Global Resource View/Projection matrix  SHOULD BE ALWAYS SET = 0

//push constants block
//layout( push_constant ) uniform constants
//{
//	mat4 render_matrix;
//} PushConstants;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inTexCoord;

//object selection
layout(location = 3) in ivec2 inInstObjID;
layout(location = 0) flat out ivec2 outInstObjID;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 fragTexCoord;

layout(location = 2) flat out int SelectX;

void main() {
//    gl_Position  = (viewproj.matrix * PushConstants.render_matrix) * vec4(inPosition, 1.0);
    gl_Position  = viewproj.matrix * vec4(inPosition, 1.0);
    fragColor    = inColor;
	fragTexCoord = inTexCoord;
	
	outInstObjID = inInstObjID;
	
	}
