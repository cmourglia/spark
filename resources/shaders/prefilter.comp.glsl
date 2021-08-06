layout(local_size_x = 8, local_size_y = 8, local_size_z = 6) in;
layout(binding = 0) uniform samplerCube envMap;
layout(binding = 1, rgba32f) writeonly uniform imageCube radianceMap;

uniform float u_roughness;
uniform vec2  u_mipSize;

#include "base_math.glsl"
#include "cubemap_helpers.glsl"
#include "pbr_utils.glsl"

const uint  sampleCount    = 1024u;
const float invSampleCount = 1.0f / float(sampleCount);

// Importance sample GGX normal distribution function for a fixed roughness value.
// This returns normalized half-vector between Li & Lo.
// For derivation see: http://blog.tobias-franke.eu/2014/03/30/notes_on_importance_sampling.html
vec3 SampleGGX(float u1, float u2, float roughness)
{
	float alpha = roughness * roughness;

	float cosTheta = sqrt((1.0 - u2) / (1.0 + (alpha * alpha - 1.0) * u2));
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta); // Trig. identity
	float phi      = TWO_PI * u1;

	// Convert to Cartesian upon return.
	return vec3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}

// GGX/Towbridge-Reitz normal distribution function.
// Uses Disney's reparametrization of alpha = roughness^2.
float NDF_GGX(float LoH, float roughness)
{
	float alpha   = roughness * roughness;
	float alphaSq = alpha * alpha;

	float denom = (LoH * LoH) * (alphaSq - 1.0) + 1.0;
	return alphaSq / (PI * denom * denom);
}

void main()
{
	ivec3 cubeCoord = ivec3(gl_GlobalInvocationID);

	// Solid angle associated with a single cubemap texel at zero mipmap level.
	// This will come in handy for importance sampling below.
	vec2  inputSize = vec2(textureSize(envMap, 0));
	float wt        = 4.0 * PI / (6 * inputSize.x * inputSize.y);

	// Approximation: Assume zero viewing angle (isotropic reflections).
	vec3 N  = normalize(CubeCoordToWorld(cubeCoord, u_mipSize));
	vec3 Lo = N;

	vec3 S, T;
	ComputeBasisVectors(N, S, T);

	vec3  color  = vec3(0);
	float weight = 0;

	// Convolve environment map using GGX NDF importance sampling.
	// Weight by cosine term since Epic claims it generally improves quality.
	for (uint i = 0; i < sampleCount; i++)
	{
		vec2 u  = SampleHammersley(i, sampleCount);
		vec3 Lh = TangentToWorld(SampleGGX(u.x, u.y, u_roughness), N, S, T);

		// Compute incident direction (Li) by reflecting viewing direction (Lo) around half-vector (Lh).
		vec3 Li = 2.0 * dot(Lo, Lh) * Lh - Lo;

		float cosLi = dot(N, Li);
		if (cosLi > 0.0)
		{
			// Use Mipmap Filtered Importance Sampling to improve convergence.
			// See: https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch20.html, section 20.4

			float LoH = max(dot(N, Lh), 0.0);

			// GGX normal distribution function (D term) probability density function.
			// Scaling by 1/4 is due to change of density in terms of Lh to Li (and since N=V, rest of the scaling factor cancels out).
			float pdf = NDF_GGX(LoH, u_roughness) * 0.25;

			// Solid angle associated with this sample.
			float ws = 1.0 / (sampleCount * pdf);

			// Mip level to sample from.
			float mipLevel = max(0.5 * log2(ws / wt) + 1.0, 0.0);

			color += textureLod(envMap, Li, mipLevel).rgb * cosLi;
			weight += cosLi;
		}
	}
	color /= weight;

	if (isnan(color.r) || isnan(color.g) || isnan(color.b))
	{
		color.rgb = vec3(1, 0, 1);
	}

	if (isnan(weight))
	{
		color.rgb = vec3(0, 1, 1);
	}

	imageStore(radianceMap, cubeCoord, vec4(color, 1.0));
}