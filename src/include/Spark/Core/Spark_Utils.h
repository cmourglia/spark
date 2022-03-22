#pragma once

#include <beard/core/macros.h>

#include <glm/vec2.hpp>
#include <chrono>

inline glm::vec2 Hammersley(u32 i, f32 invN)
{
	constexpr f32 tof  = 0.5f / 0x80000000U;
	u32           bits = i;

	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return {i * invN, bits * tof};
}

constexpr inline f32 Pow5(const f32 x)
{
	const f32 x2 = x * x;
	return x2 * x2 * x;
}

template <u32 COUNT>
constexpr inline f32 Pow(const f32 x)
{
	f32 res = 1.0f;

	for (u32 i = 0; i < COUNT; ++i)
	{
		res *= x;
	}

	return res;
}
