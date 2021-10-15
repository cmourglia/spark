#include "environment.h"

#include "renderer/program.h"
#include "renderer/render_primitives.h"
#include "renderer/frame_stats.h"

#include "core/utils.h"

#include <Beard/Macros.h>
#include <Beard/Timer.h>

#include <glad/glad.h>

#include <stb_image.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

extern std::vector<glm::vec3> PrecomputeDFG(u32 w, u32 h, u32 sampleCount); // 128, 128, 512

void LoadEnvironment(const char* filename, Environment* env)
{
	FrameStats*  stats = FrameStats::Get();
	Beard::Timer timer;
	Beard::Timer procTimer;

	if (!glIsTexture(env->iblDFG))
	{
		glCreateTextures(GL_TEXTURE_2D, 1, &env->iblDFG);

		// glTextureStorage2D(equirectangularTexture, levels, GL_RGB32F, w, h);
		glTextureStorage2D(env->iblDFG, 1, GL_RGB32F, 128, 128);

		glTextureSubImage2D(env->iblDFG, 0, 0, 0, 128, 128, GL_RGB, GL_FLOAT, PrecomputeDFG(128, 128, 1024).data());
		glTextureParameteri(env->iblDFG, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->iblDFG, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->iblDFG, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTextureParameteri(env->iblDFG, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		FrameStats::Get()->ibl.precomputeDFG = timer.Tick();
	}

	stbi_set_flip_vertically_on_load(true);

	i32  w, h, c;
	f32* data = stbi_loadf(filename, &w, &h, &c, 0);

	stbi_set_flip_vertically_on_load(false);

	if (data == nullptr)
	{
		return;
	}

	const u32 cubemapSize = 1024;

	GLuint equirectangularTexture;
	glCreateTextures(GL_TEXTURE_2D, 1, &equirectangularTexture);

	// glTextureStorage2D(equirectangularTexture, levels, GL_RGB32F, w, h);
	glTextureStorage2D(equirectangularTexture, log2f(Beard::Min(w, h)), GL_RGB32F, w, h);
	glTextureSubImage2D(equirectangularTexture, 0, 0, 0, w, h, GL_RGB, GL_FLOAT, data);
	glTextureParameteri(equirectangularTexture, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTextureParameteri(equirectangularTexture, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTextureParameteri(equirectangularTexture, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTextureParameteri(equirectangularTexture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	stbi_image_free(data);

	stats->ibl.loadTexture = timer.Tick();

	// Cleanup old data
	if (!glIsTexture(env->envMap))
	{
		glCreateTextures(GL_TEXTURE_CUBE_MAP, 1, &env->envMap);
		glTextureStorage2D(env->envMap, log2f(cubemapSize), GL_RGBA32F, cubemapSize, cubemapSize);

		glTextureParameteri(env->envMap, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->envMap, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->envMap, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->envMap, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(env->envMap, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	}

	Program* equirectangularToCubemapProgram = Program::GetProgramByName("equirectangularToCubemap");
	equirectangularToCubemapProgram->Bind();
	glBindTextureUnit(0, equirectangularTexture);
	glBindImageTexture(1, env->envMap, 0, GL_TRUE, 0, GL_WRITE_ONLY, GL_RGBA32F);

	glDispatchCompute(cubemapSize / 8, cubemapSize / 8, 1);
	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	glGenerateTextureMipmap(env->envMap);

	stats->ibl.cubemap = timer.Tick();

	if (!glIsTexture(env->radianceMap))
	{
		glCreateTextures(GL_TEXTURE_CUBE_MAP, 1, &env->radianceMap);
		glTextureStorage2D(env->radianceMap, 6, GL_RGBA32F, cubemapSize, cubemapSize);

		glTextureParameteri(env->radianceMap, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->radianceMap, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->radianceMap, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->radianceMap, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(env->radianceMap, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	}

	Program* prefilterEnvmapProgram = Program::GetProgramByName("prefilterEnvmap");
	prefilterEnvmapProgram->Bind();
	glBindTextureUnit(0, env->envMap);

	u32 mipLevels = 6;
	u32 mipSize   = cubemapSize;

	for (u32 mip = 0; mip < mipLevels; ++mip, mipSize /= 2)
	{
		const f32 roughness = Beard::Max(0.05f, (f32)mip / (f32)(mipLevels - 1));

		glBindImageTexture(1, env->radianceMap, mip, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
		prefilterEnvmapProgram->SetUniform("u_roughness", roughness);
		prefilterEnvmapProgram->SetUniform("u_mipSize", glm::vec2(mipSize, mipSize));

		glDispatchCompute(mipSize / 8, mipSize / 8, 1);
	}

	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	stats->ibl.prefilter = timer.Tick();

	if (!glIsTexture(env->irradianceMap))
	{
		glCreateTextures(GL_TEXTURE_CUBE_MAP, 1, &env->irradianceMap);

		glTextureStorage2D(env->irradianceMap, 1, GL_RGBA32F, 64, 64);

		glTextureParameteri(env->irradianceMap, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->irradianceMap, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->irradianceMap, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
		glTextureParameteri(env->irradianceMap, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(env->irradianceMap, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	}

	Program* irradianceProgram = Program::GetProgramByName("irradiance");
	irradianceProgram->Bind();
	glBindTextureUnit(0, env->radianceMap); // glBindImageTexture(0, env->envMap, 0, GL_TRUE, 0, GL_READ_ONLY, GL_RGBA32F);
	glBindImageTexture(1, env->irradianceMap, 0, GL_TRUE, 0, GL_WRITE_ONLY, GL_RGBA32F);

	glDispatchCompute(8, 8, 1);

	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	stats->ibl.irradiance = timer.Tick();
	stats->ibl.total      = procTimer.Tick();
}
