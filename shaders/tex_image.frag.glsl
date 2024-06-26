#version 460

layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inTexcoords;

layout (location = 0) out vec4 outColor;

layout (set = 0, binding = 0) uniform sampler2D displayTexture;

void main()
{
    outColor = texture(displayTexture, inTexcoords);
}
