layout(local_size_x = 8, local_size_y = 8, local_size_z = 6) in;
layout(binding = 0) uniform samplerCube envMap;
layout(binding = 1, rgba32f) writeonly uniform imageCube irradianceMap;

#include "base_math.glsl"
#include "cubemap_helpers.glsl"
#include "pbr_utils.glsl"

const float sampleTheta = TWO_PI / 360.0;
const float samplePhi   = HALF_PI / 90.0;

// Computes diffuse irradiance cubemap convolution for image-based lighting.
// Uses quasi Monte Carlo sampling with Hammersley sequence.

void main(void)
{
	vec3 N = normalize(CubeCoordToWorld(ivec3(gl_GlobalInvocationID), vec2(imageSize(irradianceMap))));

	vec3 S, T;
	ComputeBasisVectors(N, S, T);

	uint samples = 64 * 1024;

	// Monte Carlo integration of hemispherical irradiance.
	// As a small optimization this also includes Lambertian BRDF assuming perfectly white surface (albedo of 1.0)
	// so we don't need to normalize in PBR fragment shader (so technically it encodes exitant radiance rather than irradiance).
	vec3 irradiance = vec3(0);
	for (uint i = 0; i < samples; i++)
	{
		vec2  u        = SampleHammersley(i, samples);
		vec3  Li       = TangentToWorld(SampleHemisphere(u.x, u.y), N, S, T);
		float cosTheta = max(0.0, dot(Li, N));

		// PIs here cancel out because of division by pdf.
		irradiance += 2.0 * textureLod(envMap, Li, 8).rgb * cosTheta;
	}
	irradiance /= vec3(samples);

	imageStore(irradianceMap, ivec3(gl_GlobalInvocationID), vec4(irradiance, 1.0));
}
