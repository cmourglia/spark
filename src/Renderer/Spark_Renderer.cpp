#include <Spark/Renderer/Spark_Renderer.h>

#include <Spark/Renderer/Spark_RenderPrimitives.h>
#include <Spark/Renderer/Spark_FrameStats.h>

#include <Spark/World/Spark_World.h>
#include <Spark/World/Spark_Entity.h>

#include <Spark/Core/Spark_Utils.h>

#include <beard/misc/timer.h>
#include <beard/math/math.h>

#include <entt/entt.hpp>

Renderer& Renderer::Get()
{
	static Renderer renderer;
	return renderer;
}

void Renderer::Initialize(const glm::vec2& initialSize)
{
	glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);

	Program::MakeCompute("equirectangularToCubemap", "equirectangular_to_cubemap.comp.glsl");
	Program::MakeCompute("prefilterEnvmap", "prefilter.comp.glsl");
	Program::MakeCompute("irradiance", "irradiance.comp.glsl");

	m_backgroundProgram = Program::MakeRender("background", "background.vert.glsl", "background.frag.glsl");

	m_bloomProgram  = Program::MakeCompute("bloom", "bloom.comp.glsl");
	m_outputProgram = Program::MakeCompute("compose", "compose.comp.glsl");

	glCreateFramebuffers(2, m_fbos);

	Resize(initialSize);
}

void Renderer::Resize(const glm::vec2& newSize)
{
	if (m_framebufferSize != newSize)
	{
		if (glIsTexture(msaaRenderTexture))
		{
			glDeleteTextures(1, &msaaRenderTexture);
			glDeleteTextures(1, &resolveTexture);
			glDeleteTextures(1, &outputTexture);
			glDeleteTextures(3, bloomTextures);
			glDeleteRenderbuffers(1, &msaaDepthRenderBuffer);
		}

		// Create MSAA texture and attach it to FBO
		glCreateTextures(GL_TEXTURE_2D_MULTISAMPLE, 1, &msaaRenderTexture);
		glTextureStorage2DMultisample(msaaRenderTexture, 4, GL_RGBA32F, newSize.x, newSize.y, GL_TRUE);
		glNamedFramebufferTexture(m_msaaFB, GL_COLOR_ATTACHMENT0, msaaRenderTexture, 0);

		// Create MSAA DS rendertarget and attach it to FBO
		glCreateRenderbuffers(1, &msaaDepthRenderBuffer);
		glNamedRenderbufferStorageMultisample(msaaDepthRenderBuffer, 4, GL_DEPTH24_STENCIL8, newSize.x, newSize.y);
		glNamedFramebufferRenderbuffer(m_msaaFB, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, msaaDepthRenderBuffer);

		if (glCheckNamedFramebufferStatus(m_msaaFB, GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		{
			fprintf(stderr, "MSAA framebuffer incomplete\n");
		}

		glCreateTextures(GL_TEXTURE_2D, 1, &resolveTexture);
		glTextureStorage2D(resolveTexture, 1, GL_RGBA32F, newSize.x, newSize.y);
		glNamedFramebufferTexture(m_resolveFB, GL_COLOR_ATTACHMENT0, resolveTexture, 0);
		glTextureParameteri(resolveTexture, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(resolveTexture, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

		if (glCheckNamedFramebufferStatus(m_resolveFB, GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		{
			fprintf(stderr, "Resolve framebuffer incomplete\n");
		}

		glCreateTextures(GL_TEXTURE_2D, 1, &outputTexture);
		glTextureStorage2D(outputTexture, 1, GL_RGBA8, newSize.x, newSize.y);

		m_bloomSize = newSize * 0.5f;
		m_bloomSize.x += m_bloomComputeWorkGroupSize - ((i32)m_bloomSize.x % m_bloomComputeWorkGroupSize);
		m_bloomSize.y += m_bloomComputeWorkGroupSize - ((i32)m_bloomSize.y % m_bloomComputeWorkGroupSize);

		i32 mipCount  = log2(beard::min(m_bloomSize.x, m_bloomSize.y));
		m_bloomPasses = mipCount - 2;
		glCreateTextures(GL_TEXTURE_2D, 3, bloomTextures);
		glTextureStorage2D(bloomTextures[0], mipCount, GL_RGBA32F, m_bloomSize.x, m_bloomSize.y);
		glTextureStorage2D(bloomTextures[1], mipCount, GL_RGBA32F, m_bloomSize.x, m_bloomSize.y);
		glTextureStorage2D(bloomTextures[2], mipCount, GL_RGBA32F, m_bloomSize.x, m_bloomSize.y);

		glTextureParameteri(bloomTextures[0], GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(bloomTextures[0], GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTextureParameteri(bloomTextures[0], GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
		glTextureParameteri(bloomTextures[0], GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

		glTextureParameteri(bloomTextures[1], GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(bloomTextures[1], GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTextureParameteri(bloomTextures[1], GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
		glTextureParameteri(bloomTextures[1], GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

		glTextureParameteri(bloomTextures[2], GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
		glTextureParameteri(bloomTextures[2], GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTextureParameteri(bloomTextures[2], GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
		glTextureParameteri(bloomTextures[2], GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);

		m_framebufferSize = newSize;
	}
}

void Renderer::Render(const World& world)
{
	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;
	beard::timer frameTimer;

	Program::UpdateAllPrograms();
	stats->frame.updatePrograms = timer.tick();

	ShadowPass(world);
	LightPass(world);
	ResolveMSAA();
	Bloom();
	Compose();

	stats->renderTotal = frameTimer.tick();
}

void Renderer::ShadowPass(const World& world)
{
	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;
}

void Renderer::LightPass(const World& world)
{
	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;

	auto  camera          = world.GetActiveCamera();
	auto& cameraComponent = camera.GetComponent<CameraComponent>();

	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_msaaFB);

	glViewport(0, 0, m_framebufferSize.x, m_framebufferSize.y);

	glClearDepth(1.0f);
	glClearColor(0.5f, 0.8f, 0.9f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LEQUAL);

	RenderContext context{
	    .eyePosition = cameraComponent.position,
	    .view        = camera.GetTransform(),
	    .proj        = cameraComponent.proj,
	    .env         = &env,
	};

	auto view = world.GetRegistry().view<const TransformComponent, Renderable>();
	view.each(
	    [&context](const auto& transform, auto& renderable)
	    {
		    Model model;
		    model.worldTransform = transform.transform;
		    model.mesh           = renderable.mesh.get();
		    model.material       = renderable.material.get();
		    model.Draw(&context);
	    });

	stats->frame.renderModels = timer.Tick();

	if (backgroundType != BackgroundType::None)
	{
		m_backgroundProgram->Bind();
		m_backgroundProgram->SetUniform("envmap", 0);
		m_backgroundProgram->SetUniform("miplevel", backgroundType == BackgroundType::Radiance ? backgroundMipLevel : 0);
		m_backgroundProgram->SetUniform("view", context.view);
		m_backgroundProgram->SetUniform("proj", context.proj);

		switch (backgroundType)
		{
			case BackgroundType::Cubemap:
				glBindTextureUnit(0, env.envMap);
				break;

			case BackgroundType::Radiance:
				glBindTextureUnit(0, env.radianceMap);
				break;

			case BackgroundType::Irradiance:
				glBindTextureUnit(0, env.irradianceMap);
				break;
		}

		RenderCube();
	}

	stats->frame.background = timer.tick();
}

void Renderer::ResolveMSAA()
{
	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;

	glBlitNamedFramebuffer(m_msaaFB,
	                       m_resolveFB,
	                       0,
	                       0,
	                       m_framebufferSize.x,
	                       m_framebufferSize.y,
	                       0,
	                       0,
	                       m_framebufferSize.x,
	                       m_framebufferSize.y,
	                       GL_COLOR_BUFFER_BIT,
	                       GL_NEAREST);

	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);

	stats->frame.resolveMSAA = timer.tick();
}

void Renderer::Bloom()
{
	if (!bloom.enabled)
	{
		return;
	}

	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;

	beard::timer bloomTimer;

	m_bloomProgram->Bind();

	u32 workGroupsX = m_bloomSize.x / m_bloomComputeWorkGroupSize;
	u32 workGroupsY = m_bloomSize.y / m_bloomComputeWorkGroupSize;

	u32 width  = m_bloomSize.x;
	u32 height = m_bloomSize.y;

	// Prefilter
	glBindImageTexture(0, bloomTextures[0], 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
	glBindTextureUnit(1, resolveTexture);
	glBindTextureUnit(2, resolveTexture);
	m_bloomProgram->SetUniform("u_mode", 0);
	m_bloomProgram->SetUniform("u_lod", 0.0f);
	m_bloomProgram->SetUniform("u_params", glm::vec4(bloom.threshold, bloom.threshold - bloom.knee, bloom.knee * 2.0f, 0.25f / bloom.knee));
	glDispatchCompute(workGroupsX, workGroupsY, 1);
	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
	stats->frame.bloomPrefilter = timer.tick();

	// Downsample
	m_bloomProgram->SetUniform("u_mode", 1);

	f32 lod = 1.0f;
	for (u32 i = 1; i < m_bloomPasses; ++i, lod += 1.0f)
	{
		u32 mipWidth  = (u32)m_bloomSize.x >> i;
		u32 mipHeight = (u32)m_bloomSize.y >> i;

		workGroupsX = ceil((f32)mipWidth / (f32)m_bloomComputeWorkGroupSize);
		workGroupsY = ceil((f32)mipHeight / (f32)m_bloomComputeWorkGroupSize);

		m_bloomProgram->SetUniform("u_lod", lod - 1);
		glBindImageTexture(0, bloomTextures[1], i, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
		glBindTextureUnit(1, bloomTextures[0]);
		glBindTextureUnit(2, resolveTexture);
		glDispatchCompute(workGroupsX, workGroupsY, 1);
		glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

		m_bloomProgram->SetUniform("u_lod", lod);
		glBindImageTexture(0, bloomTextures[0], i, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
		glBindTextureUnit(1, bloomTextures[1]);
		glBindTextureUnit(2, resolveTexture);
		glDispatchCompute(workGroupsX, workGroupsY, 1);
		glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
	}
	stats->frame.bloomDownsample = timer.tick();

	lod -= 1.0f;

	u32 mipWidth  = (u32)m_bloomSize.x >> m_bloomPasses;
	u32 mipHeight = (u32)m_bloomSize.y >> m_bloomPasses;

	workGroupsX = ceil((f32)mipWidth / (f32)m_bloomComputeWorkGroupSize);
	workGroupsY = ceil((f32)mipHeight / (f32)m_bloomComputeWorkGroupSize);

	// First upsample
	m_bloomProgram->SetUniform("u_mode", 2);
	m_bloomProgram->SetUniform("u_lod", lod);
	glBindImageTexture(0, bloomTextures[2], m_bloomPasses, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
	glBindTextureUnit(1, bloomTextures[0]);
	glBindTextureUnit(2, resolveTexture);
	glDispatchCompute(workGroupsX, workGroupsY, 1);
	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
	stats->frame.bloomUpsampleFirst = timer.tick();

	// Upsample
	m_bloomProgram->SetUniform("u_mode", 3);

	for (i32 mip = m_bloomPasses - 1; mip >= 0; mip--)
	{
		u32 mipWidth  = (u32)m_bloomSize.x >> mip;
		u32 mipHeight = (u32)m_bloomSize.y >> mip;

		workGroupsX = ceil((f32)mipWidth / (f32)m_bloomComputeWorkGroupSize);
		workGroupsY = ceil((f32)mipHeight / (f32)m_bloomComputeWorkGroupSize);

		m_bloomProgram->SetUniform("u_lod", (f32)mip);
		glBindImageTexture(0, bloomTextures[2], mip, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
		glBindTextureUnit(1, bloomTextures[0]);
		glBindTextureUnit(2, bloomTextures[2]);
		glDispatchCompute(workGroupsX, workGroupsY, 1);
		glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
	}

	stats->frame.bloomUpsample = timer.tick();
	stats->frame.bloomTotal    = bloomTimer.tick();
}

void Renderer::Compose()
{
	FrameStats*  stats = FrameStats::Get();
	beard::timer timer;

	// Final render
	m_outputProgram->Bind();
	m_outputProgram->SetUniform("viewportSize", m_framebufferSize);
	m_outputProgram->SetUniform("bloomAmount", bloom.enabled ? bloom.intensity : 0.0f);

	glBindImageTexture(0, outputTexture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);
	glBindTextureUnit(1, resolveTexture);
	glBindTextureUnit(2, bloomTextures[0]);
	glBindTextureUnit(3, bloomTextures[1]);
	glBindTextureUnit(4, bloomTextures[2]);

	glDispatchCompute(m_framebufferSize.x / 32, m_framebufferSize.y / 32, 1);

	glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

	stats->frame.finalCompositing = timer.tick();
}

void Model::Draw(RenderContext* context) const
{
	context->model = worldTransform;

	Program* program = material->GetProgram();

	program->Bind();

	program->SetUniform("u_eye", context->eyePosition);
	program->SetUniform("u_model", context->model);
	program->SetUniform("u_view", context->view);
	program->SetUniform("u_proj", context->proj);

	material->Bind(program, context->env);

	mesh->Draw();
}
