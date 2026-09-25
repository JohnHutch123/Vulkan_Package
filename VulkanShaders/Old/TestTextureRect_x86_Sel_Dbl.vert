#version 450
#extension GL_ARB_gpu_shader_fp64 : require

//SET = 0 Global Resource Set
//SET = 1 Graphic Pipeline Resource SET4//Set = 2 Node Material properties Resource SET
//Set = 3 Node ID/Position Resource SET 

layout(set = 0, binding = 0, std140) uniform ViewProjBufferObject {
    dmat4 matrix;
} tranviewproj;
// Global Resource View/Projection matrix SHOULD BE ALWAYS SET = 0

//select layout at Set 3
layout(push_constant, set = 3, binding = 0) uniform IntUB {
    int value;
} ObjectIDBuf;

// Push constants block used for local transform of node during a Move/Rotate/Stretch
layout(push_constant, std430) uniform constants {
    dmat4 node_matrix;
} NodeConstant;

layout(location = 0) in vec3 inPosition; 
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inTexCoord;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 fragTexCoord;
layout(location = 2) flat out int ObjectID;

void main() {

//    dvec4 pos = ((tranviewproj.matrix * NodeConstant.node_matrix)  * dvec4(inPosition, 1.0));
    dvec4 pos = (tranviewproj.matrix   * dvec4(inPosition, 1.0));
    gl_Position = vec4(pos);  
	
    fragColor = inColor;
    fragTexCoord = inTexCoord;
	
	ObjectID = ObjectIDBuf.value;
}