#version 450
#extension GL_ARB_gpu_shader_fp64 : require

layout(set = 1, binding = 0) uniform sampler2D texSampler;
// Graphic Pipe (Node Group) Texture 
// ALL nodes using this GraphicPipe have access to this texture
// SET = 1 if Global Resource used

// vertex location data
layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

//Instance
layout(location = 2) in ivec2 inInstObjID;

layout(location = 0) out vec4 outColor;

// Storage Image for storage of ObjectID
// Global descriptor SET = 0 and Binding = 1
layout(set = 0, binding = 1, r32ui) uniform uimage2D outBuffer;

void main() {

    vec3 texColor = texture(texSampler, fragTexCoord).rgb;
    outColor = vec4(fragColor * texColor, 1.0);
	
	ivec2 coord = ivec2(gl_FragCoord.xy);
    ivec4 ObjID = ivec4(float(inInstObjID,x), float(inInstObjID,y), 0, 0); // Only first two channels are used
	
    imageStore(outBuffer, coord, ObjID);		
	
}