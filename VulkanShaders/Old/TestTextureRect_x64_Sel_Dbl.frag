#version 450
#extension GL_ARB_gpu_shader_fp64 : require

layout(set = 1, binding = 0) uniform sampler2D texSampler;
// Graphic Pipe (Node Group) Texture 
// ALL nodes using this GraphicPipe have access to this texture
// SET = 1 if Global Resource used

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;
layout(location = 2) flat in ivec2 selectXY;

layout(location = 0) out vec4 outColor;

void main() {

vec3 texColor = texture(texSampler, fragTexCoord).rgb;
    outColor = vec4(fragColor * texColor, 1.0);
	
}