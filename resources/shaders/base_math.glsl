#ifndef BASE_MATH_GLSL
#define BASE_MATH_GLSL

const float PI      = 3.14159265359;
const float INV_PI  = 1.0 / 0.31830988618;
const float TWO_PI  = PI * 2.0;
const float HALF_PI = PI * 0.5;
const float EPSILON = 1e-5f;

float saturate(float x)
{
	return clamp(x, 0.0, 1.0);
}

float Pow5(float x)
{
	const float x2 = x * x;
	return x2 * x2 * x;
}

// Uniformly sample point on a hemisphere.
// Cosine-weighted sampling would be a better fit for Lambertian BRDF but since this
// compute shader runs only once as a pre-processing step performance is not *that* important.
// See: "Physically Based Rendering" 2nd ed., section 13.6.1.
vec3 SampleHemisphere(float u1, float u2)
{
	const float u1p = sqrt(max(0.0, 1.0 - u1 * u1));
	return vec3(cos(TWO_PI * u2) * u1p, sin(TWO_PI * u2) * u1p, u1);
}

// Compute orthonormal basis for converting from tanget/shading space to world space.
void ComputeBasisVectors(const vec3 N, out vec3 S, out vec3 T)
{
	// Branchless select non-degenerate T.
	T = cross(N, vec3(0.0, 1.0, 0.0));
	T = mix(cross(N, vec3(1.0, 0.0, 0.0)), T, step(EPSILON, dot(T, T)));

	T = normalize(T);
	S = normalize(cross(N, T));
}

// Convert point from tangent/shading space to world space.
vec3 TangentToWorld(const vec3 v, const vec3 N, const vec3 S, const vec3 T)
{
	return S * v.x + T * v.y + N * v.z;
}

float rcp(float x)
{
	return 1.0 / x;
}

vec2 rcp(vec2 x)
{
	return 1.0 / x;
}

vec3 rcp(vec3 x)
{
	return 1.0 / x;
}

vec4 rcp(vec4 x)
{
	return 1.0 / x;
}

#endif // BASE_MATH_GLSL