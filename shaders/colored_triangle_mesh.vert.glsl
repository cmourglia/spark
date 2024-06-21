#version 460
#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;
layout (location = 1) out vec2 outUV;

struct Vertex {
    vec3 position;
    float uvX;
    vec3 normal;
    float uvY;
    vec4 color;
};

layout (buffer_reference, std430) readonly buffer VertexBuffer {
    Vertex vertices[];
};

layout (push_constant) uniform constants {
    mat4 worldMatrix;
    VertexBuffer vertexBuffer;
};

void main()
{
    Vertex v = vertexBuffer.vertices[gl_VertexIndex];

    gl_Position = worldMatrix * vec4(v.position, 1.0);
    outColor = v.color.rgb;
    outUV = vec2(v.uvX, v.uvY);
}
