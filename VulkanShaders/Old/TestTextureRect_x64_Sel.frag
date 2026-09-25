#version 450

layout(set = 1, binding = 0) uniform sampler2D texSampler;

//Graphic Pipe (Node Group) Texture 
//ALL nodes using this GraphicPipe have access to this textuure
//SET = 1 if Global Resource used


layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {

    vec3 texColor = texture(texSampler, fragTexCoord).rgb;
    outColor = vec4(fragColor * texColor, 1.0);
	
}