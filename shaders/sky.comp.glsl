#version 460

layout (local_size_x = 16, local_size_y = 16) in;
layout (rgba16f, set = 0, binding = 0) uniform image2D image;

layout (push_constant) uniform constants {
    vec4 data1;
    vec4 data2;
    vec4 data3;
    vec4 data4;
} PushConstants;

float Noise2D(vec2 x)
{
    float xhash = cos(x.x * 37.0);
    float yhash = cos(x.y * 57.0);
    return fract(415.92653 * (xhash + yhash));
}

float NoisyStarField(vec2 samplePos, float threshold)
{
    float starVal = Noise2D(samplePos);
    if (starVal >= threshold)
    {
        starVal = pow((starVal - threshold) / (1.0 - threshold), 6.0);
    }
    else
    {
        starVal = 0.0;
    }

    return starVal;
}

float StableStarField(vec2 samplePos, float threshold)
{
    float fractX = fract(samplePos.x);
    float fractY = fract(samplePos.x);
    vec2 floorSample = floor(samplePos);
    float v1 = NoisyStarField(floorSample + vec2(0.0, 0.0), threshold);
    float v2 = NoisyStarField(floorSample + vec2(0.0, 1.0), threshold);
    float v3 = NoisyStarField(floorSample + vec2(1.0, 0.0), threshold);
    float v4 = NoisyStarField(floorSample + vec2(1.0, 1.0), threshold);

    float starVal = v1 * (1 - fractX) * (1 - fractY)
                  + v2 * (1 - fractX) *      fractY
                  + v3 *      fractX  * (1 - fractY)
                  + v4 *      fractX  *      fractY;

    return starVal;
}

vec4 mainImage(vec2 fragCoord)
{
    vec2 resolution = imageSize(image);
    vec3 color = PushConstants.data1.xyz * fragCoord.y / resolution.y;

    float starFieldThreshold = PushConstants.data1.w;

    float xRate = 0.2;
    float yRate = -0.96;
    vec2 samplePos = fragCoord.xy + vec2(xRate, yRate);
    float starVal = StableStarField(samplePos, starFieldThreshold);
    color += vec3(starVal);

    return vec4(color, 1.0);
}

void main()
{
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(image);
    if (texelCoord.x < size.x && texelCoord.y < size.y)
    {
        imageStore(image, texelCoord, mainImage(texelCoord));
    }
}
