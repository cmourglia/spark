layout(local_size_x = 4, local_size_y = 4) in;

layout(rgba32f, binding = 0) writeonly restrict uniform image2D outImage;

layout(binding = 1) uniform sampler2D u_colorTexture;
layout(binding = 2) uniform sampler2D u_bloomTexture;

uniform vec4  u_params;
uniform float u_lod;
uniform int   u_mode;

#define PREFILTER 0
#define DOWNSAMPLE 1
#define UPSAMPLE_FIRST_PASS 2
#define UPSAMPLE 3

#include "colors.glsl"

vec3 WeightedColor(sampler2D tex, float lod, vec2 uv, vec2 texelSize, vec2 offset, out float weightSum)
{
	vec3  color = textureLod(tex, uv + texelSize * offset, lod).rgb;
	float w     = 1.0 / (Luminance(color) + 1.0);
	weightSum += w;
	color *= w;
	return color;
}

vec3 DownsampleBox13(sampler2D tex, float lod, vec2 uv, vec2 texelSize)
{
	float weightedSum = 0.0;

	// Center
	vec3 c0 = WeightedColor(tex, lod, uv, texelSize, vec2(0.0, 0.0), weightedSum);

	texelSize *= 0.5f;

	// Inner box
	vec3 i0 = WeightedColor(tex, lod, uv, texelSize, vec2(-1.0f, -1.0f), weightedSum).rgb;
	vec3 i1 = WeightedColor(tex, lod, uv, texelSize, vec2(-1.0f, 1.0f), weightedSum).rgb;
	vec3 i2 = WeightedColor(tex, lod, uv, texelSize, vec2(1.0f, 1.0f), weightedSum).rgb;
	vec3 i3 = WeightedColor(tex, lod, uv, texelSize, vec2(1.0f, -1.0f), weightedSum).rgb;

	// Outer box
	vec3 o0 = WeightedColor(tex, lod, uv, texelSize, vec2(-2.0f, -2.0f), weightedSum).rgb;
	vec3 o1 = WeightedColor(tex, lod, uv, texelSize, vec2(-2.0f, 0.0f), weightedSum).rgb;
	vec3 o2 = WeightedColor(tex, lod, uv, texelSize, vec2(-2.0f, 2.0f), weightedSum).rgb;
	vec3 o3 = WeightedColor(tex, lod, uv, texelSize, vec2(0.0f, -2.0f), weightedSum).rgb;
	vec3 o4 = WeightedColor(tex, lod, uv, texelSize, vec2(0.0f, 2.0f), weightedSum).rgb;
	vec3 o5 = WeightedColor(tex, lod, uv, texelSize, vec2(2.0f, -2.0f), weightedSum).rgb;
	vec3 o6 = WeightedColor(tex, lod, uv, texelSize, vec2(2.0f, 0.0f), weightedSum).rgb;
	vec3 o7 = WeightedColor(tex, lod, uv, texelSize, vec2(2.0f, 2.0f), weightedSum).rgb;

	vec3 result = vec3(0.0);

	// Inner box
	result += (i0 + i1 + i2 + i3) * 0.5f;

	// Outer boxes
	result += (c0 + o0 + o1 + o3) * 0.125f;
	result += (c0 + o1 + o2 + o4) * 0.125f;
	result += (c0 + o3 + o5 + o6) * 0.125f;
	result += (c0 + o4 + o6 + o7) * 0.125f;

	// Four samples
	result *= 0.25;

	result /= weightedSum;

	return result;
}

// curve = (threshold - knee, knee * 2, 0.25 / knee)
vec4 QuadraticThreshold(vec4 color, float threshold, vec3 curve)
{
	// Maximum pixel brightness
	// TODO: Use luminance ?
	float brightness = max(max(color.r, color.g), color.b);

	float rq = clamp(brightness - curve.x, 0.0, curve.y);
	rq       = (rq * rq) * curve.z;
	color *= max(rq, brightness - threshold) / max(brightness, 1e-4);
	return color;
}

vec4 Prefilter(vec4 color, vec2 uv)
{
	float clampValue = 20.0f;
	color            = min(vec4(clampValue), color);
	color            = QuadraticThreshold(color, u_params.x, u_params.yzw);
	return color;
}

vec3 UpsampleTent9(sampler2D tex, float lod, vec2 uv, vec2 texelSize, float radius)
{
	vec4 offset = texelSize.xyxy * vec4(1.0f, 1.0f, -1.0f, 0.0f) * radius;

	// Center
	vec3 result = textureLod(tex, uv, lod).rgb * 4.0f;

	result += textureLod(tex, uv - offset.xy, lod).rgb;
	result += textureLod(tex, uv - offset.wy, lod).rgb * 2.0f;
	result += textureLod(tex, uv - offset.zy, lod).rgb;

	result += textureLod(tex, uv + offset.zw, lod).rgb * 2.0f;
	result += textureLod(tex, uv + offset.xw, lod).rgb * 2.0f;

	result += textureLod(tex, uv + offset.zy, lod).rgb;
	result += textureLod(tex, uv + offset.wy, lod).rgb * 2.0f;
	result += textureLod(tex, uv + offset.xy, lod).rgb;

	return result * (1.0f / 16.0f);
}

void main()
{
	vec2 size = vec2(imageSize(outImage));

	ivec2 texel = ivec2(gl_GlobalInvocationID);
	vec2  uv    = vec2(texel) / size;

	vec2 texSize = vec2(textureSize(u_colorTexture, int(u_lod)));
	vec4 color   = vec4(1, 1, 0, 1);

	switch (u_mode)
	{
		case PREFILTER:
		{
			uv += (1.0f / size) * 0.5f;
			color.rgb = DownsampleBox13(u_colorTexture, 0, uv, 1.0f / texSize);
			color     = Prefilter(color, uv);
			color.a   = 1.0f;
		}
		break;

		case DOWNSAMPLE:
		{
			uv += (1.0f / size) * 0.5f;
			color.rgb = DownsampleBox13(u_colorTexture, u_lod, uv, 1.0f / texSize);
		}
		break;

		case UPSAMPLE_FIRST_PASS:
		{
			vec2  bloomTexSize     = vec2(textureSize(u_colorTexture, int(u_lod + 1)));
			float sampleScale      = 1.0f;
			vec3  upsampledTexture = UpsampleTent9(u_colorTexture, u_lod + 1.0f, uv, 1.0f / bloomTexSize, sampleScale);

			vec3 existing = textureLod(u_colorTexture, uv, u_lod).rgb;
			color.rgb     = existing + upsampledTexture;
		}
		break;

		case UPSAMPLE:
		{
			// uv += (0.5 / size) * 0.5f;
			vec2  bloomTexSize     = vec2(textureSize(u_bloomTexture, int(u_lod + 1)));
			float sampleScale      = 1.0f;
			vec3  upsampledTexture = UpsampleTent9(u_bloomTexture, u_lod + 1.0f, uv, 1.0f / bloomTexSize, sampleScale);

			vec3 existing = textureLod(u_colorTexture, uv, u_lod).rgb;
			color.rgb     = existing + upsampledTexture;
		}
		break;
	}

	imageStore(outImage, texel, color);
}
