#include "renderer.h"

#include "renderer/render_primitives.h"
#include "renderer/frame_stats.h"

#include "core/utils.h"

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

		i32 mipCount  = log2(Min(m_bloomSize.x, m_bloomSize.y));
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

void Renderer::Render(const CameraInfos& camera, const Scene& scene)
{
	FrameStats* stats = FrameStats::Get();
	Timer       timer;
	Timer       frameTimer;

	Program::UpdateAllPrograms();
	stats->frame.updatePrograms = timer.Tick();

	ShadowPass(scene);
	LightPass(camera, scene);
	ResolveMSAA();
	Bloom();
	Compose();

	stats->renderTotal = frameTimer.Tick();
}

void Renderer::ShadowPass(const Scene& scene)
{
	FrameStats* stats = FrameStats::Get();
	Timer       timer;
}

void Renderer::LightPass(const CameraInfos& camera, const Scene& scene)
{
	FrameStats* stats = FrameStats::Get();
	Timer       timer;

	glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_msaaFB);

	glViewport(0, 0, m_framebufferSize.x, m_framebufferSize.y);

	glClearDepth(1.0f);
	glClearColor(0.5f, 0.8f, 0.9f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

	glEnable(GL_DEPTH_TEST);
	glDepthFunc(GL_LEQUAL);

	RenderContext context = {
	    .eyePosition = camera.position,
	    .view        = camera.view,
	    .proj        = camera.proj,
	    .env         = &scene.env,
	};

	for (auto&& model : scene.models)
	{
		model.Draw(&context);
	}

	stats->frame.renderModels = timer.Tick();

	if (backgroundType != BackgroundType_None)
	{
		m_backgroundProgram->Bind();
		m_backgroundProgram->SetUniform("envmap", 0);
		m_backgroundProgram->SetUniform("miplevel", backgroundType == BackgroundType_Radiance ? backgroundMipLevel : 0);
		m_backgroundProgram->SetUniform("view", context.view);
		m_backgroundProgram->SetUniform("proj", context.proj);

		switch (backgroundType)
		{
			case BackgroundType_Cubemap:
				glBindTextureUnit(0, scene.env.envMap);
				break;

			case BackgroundType_Radiance:
				glBindTextureUnit(0, scene.env.radianceMap);
				break;

			case BackgroundType_Irradiance:
				glBindTextureUnit(0, scene.env.irradianceMap);
				break;
		}

		RenderCube();
	}

	stats->frame.background = timer.Tick();
}

void Renderer::ResolveMSAA()
{
	FrameStats* stats = FrameStats::Get();
	Timer       timer;

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

	stats->frame.resolveMSAA = timer.Tick();
}

void Renderer::Bloom()
{
	if (!bloom.enabled)
	{
		return;
	}

	FrameStats* stats = FrameStats::Get();
	Timer       timer;

	Timer bloomTimer;

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
	stats->frame.bloomPrefilter = timer.Tick();

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
	stats->frame.bloomDownsample = timer.Tick();

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
	stats->frame.bloomUpsampleFirst = timer.Tick();

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

	stats->frame.bloomUpsample = timer.Tick();
	stats->frame.bloomTotal    = bloomTimer.Tick();
}

void Renderer::Compose()
{
	FrameStats* stats = FrameStats::Get();
	Timer       timer;

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

	stats->frame.finalCompositing = timer.Tick();
}

GLsizeiptr LayoutItem::GetSize() const
{
	GLsizeiptr dataSize = 0;

	switch (dataType)
	{
		case DataType_Byte:
		case DataType_UnsignedByte:
			assert(sizeof(GLbyte) == sizeof(GLubyte));
			dataSize = sizeof(GLbyte);
			break;

		case DataType_Short:
		case DataType_UnsignedShort:
		case DataType_HalfFloat:
			assert(sizeof(GLshort) == sizeof(GLushort));
			assert(sizeof(GLshort) == sizeof(GLhalf));
			dataSize = sizeof(GLshort);
			break;

		case DataType_Int:
		case DataType_UnsignedInt:
		case DataType_Float:
			assert(sizeof(GLint) == sizeof(GLuint));
			assert(sizeof(GLint) == sizeof(GLfloat));
			dataSize = sizeof(GLint);
			break;
	}

	return dataSize * (GLsizeiptr)elementType;
}

Mesh::Mesh()
{
}

Mesh::Mesh(const std::vector<Vertex>& vertices, const std::vector<GLushort>& indices)
    : indexCount(indices.size())
    , vertexCount(vertices.size())
    , indexType(GL_UNSIGNED_SHORT)
{
	SetData(vertices, indices);
}

Mesh::Mesh(const std::vector<Vertex>& vertices, const std::vector<GLuint>& indices)
    : indexCount(indices.size())
    , vertexCount(vertices.size())
    , indexType(GL_UNSIGNED_INT)
{
	SetData(vertices, indices);
}

Mesh::Mesh(const VertexDataInfos& vertexDataInfos, const IndexDataInfos& indexDataInfos)
    : indexCount(indexDataInfos.indexCount)
    , vertexCount(vertexDataInfos.bufferSize / vertexDataInfos.byteStride)
    , indexType(indexDataInfos.indexType)
{
	GLint alignment = GL_NONE;
	glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &alignment);

	glCreateVertexArrays(1, &vao);

	const GLsizeiptr alignedIndexSize = AlignedSize(indexDataInfos.bufferSize, alignment);

	GLsizeiptr alignedVertexSize = 0;

	if (vertexDataInfos.singleBuffer)
	{
		alignedVertexSize = AlignedSize(vertexDataInfos.bufferSize, alignment);
	}
	else
	{
		for (const auto& entry : vertexDataInfos.layout)
		{
			alignedVertexSize += AlignedSize(entry.dataSize, alignment);
		}
	}

	glCreateBuffers(1, &buffer);
	glNamedBufferStorage(buffer, alignedIndexSize + alignedVertexSize, nullptr, GL_DYNAMIC_STORAGE_BIT);

	glNamedBufferSubData(buffer, 0, indexDataInfos.bufferSize, indexDataInfos.data);
	glVertexArrayElementBuffer(vao, buffer);

	if (vertexDataInfos.singleBuffer)
	{
		i32        vboIndex   = 0;
		GLsizeiptr vboBasePtr = alignedIndexSize;

		const GLubyte* data = vertexDataInfos.layout[0].data;
		glNamedBufferSubData(buffer, vboBasePtr, vertexDataInfos.bufferSize, data);

		for (const auto& entry : vertexDataInfos.layout)
		{
			assert(entry.data == data);

			glEnableVertexArrayAttrib(vao, entry.bindingPoint);
			glVertexArrayAttribBinding(vao, entry.bindingPoint, vboIndex);

			if (vertexDataInfos.interleaved)
			{
				glVertexArrayVertexBuffer(vao, vboIndex, buffer, vboBasePtr, vertexDataInfos.byteStride);
				glVertexArrayAttribFormat(vao, entry.bindingPoint, entry.elementType, entry.dataType, GL_FALSE, entry.offset);
			}
			else
			{
				vboBasePtr += entry.offset;

				glVertexArrayVertexBuffer(vao, vboIndex, buffer, vboBasePtr, entry.GetSize());
				glVertexArrayAttribFormat(vao, entry.bindingPoint, entry.elementType, entry.dataType, GL_FALSE, 0);

				++vboIndex;
			}
		}
	}
	else
	{
		i32        vboIndex   = 0;
		GLsizeiptr vboBasePtr = alignedIndexSize;

		std::unordered_map<const GLubyte*, GLsizeiptr> insertedData;

		for (const auto& entry : vertexDataInfos.layout)
		{
			if (insertedData.find(entry.data) == insertedData.end())
			{
				glNamedBufferSubData(buffer, vboBasePtr, entry.dataSize, entry.data);

				glVertexArrayVertexBuffer(vao, vboIndex, buffer, vboBasePtr, entry.GetSize());

				insertedData[entry.data] = vboBasePtr;

				vboBasePtr += AlignedSize(entry.dataSize, alignment);
			}
			else
			{
				glVertexArrayVertexBuffer(vao, vboIndex, buffer, insertedData[entry.data] + entry.offset, entry.GetSize());
			}

			glVertexArrayAttribFormat(vao, entry.bindingPoint, entry.elementType, entry.dataType, GL_FALSE, 0);
			glEnableVertexArrayAttrib(vao, entry.bindingPoint);
			glVertexArrayAttribBinding(vao, entry.bindingPoint, vboIndex);

			++vboIndex;
		}
	}
}

GLsizeiptr Mesh::AlignedSize(GLsizeiptr size, GLsizeiptr align)
{
	return size;
	if (size % align == 0)
		return size;
	return size + (align - size % align);
}

void Mesh::SetLayout(const Layout& layout, const std::vector<GLsizeiptr>& offsets)
{
	assert(offsets.size() == layout.size());
	for (size_t i = 0; i < layout.size(); ++i)
	{
		const auto& entry = layout[i];
		glEnableVertexArrayAttrib(vao, entry.bindingPoint);
		glVertexArrayAttribFormat(vao, entry.bindingPoint, entry.elementType, entry.dataType, GL_FALSE, offsets[i]);
		glVertexArrayAttribBinding(vao, entry.bindingPoint, 0);
	}
}

void Mesh::Draw() const
{
	glBindVertexArray(vao);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer);
	glDrawElements(GL_TRIANGLES, indexCount, indexType, nullptr);
}

void Mesh::DrawInstanced(u32 instanceCount) const
{
	glBindVertexArray(vao);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffer);
	glDrawElementsInstanced(GL_TRIANGLES, indexCount, indexType, nullptr, instanceCount);
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
