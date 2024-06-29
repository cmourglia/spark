#version 460

layout (local_size_x = 16, local_size_y = 16) in;

layout (rgba16f, set = 0, binding = 0) uniform image2D image;

layout (std430, set = 0, binding = 1) readonly buffer Pixel_Data {
    vec4 colors[];
} pixels;

void main()
{
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);

    ivec2 size = imageSize(image);

    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        vec4 color = pixels.colors[texelCoord.y * size.x + texelCoord.x];

        imageStore(image, texelCoord, color);
    }
}
