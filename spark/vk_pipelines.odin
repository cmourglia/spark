package spark

import "core:log"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

LoadShaderModule :: proc(device: vk.Device, filepath: string) -> (vk.ShaderModule, b32) {
	shaderModule: vk.ShaderModule

	content, ok := os.read_entire_file(filepath, context.temp_allocator)
	if !ok {
		log.errorf("Could not read file '%s'\n", filepath)
		return shaderModule, false
	}

	code := slice.reinterpret([]u32, content)

	shaderModuleInfo := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(content),
		pCode    = raw_data(code),
	}

	check(vk.CreateShaderModule(device, &shaderModuleInfo, nil, &shaderModule))

	return shaderModule, true
}

GraphicsPipelineConfig :: struct {
	shaderStages:          [dynamic]vk.PipelineShaderStageCreateInfo,
	inputAssembly:         vk.PipelineInputAssemblyStateCreateInfo,
	rasterizer:            vk.PipelineRasterizationStateCreateInfo,
	colorBlendAttachment:  vk.PipelineColorBlendAttachmentState,
	multisampling:         vk.PipelineMultisampleStateCreateInfo,
	depthStencil:          vk.PipelineDepthStencilStateCreateInfo,
	renderInfo:            vk.PipelineRenderingCreateInfo,
	pipelineLayout:        vk.PipelineLayout,
	colorAttachmentFormat: vk.Format,
}

DefaultGraphicsPipelineConfig :: proc() -> GraphicsPipelineConfig {
	config := GraphicsPipelineConfig {
		inputAssembly = {sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO},
		rasterizer = {sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO},
		multisampling = {sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO},
		depthStencil = {sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO},
		renderInfo = {sType = .PIPELINE_RENDERING_CREATE_INFO},
	}

	return config
}


BuildGraphicsPipeline :: proc(
	device: vk.Device,
	using config: ^GraphicsPipelineConfig,
) -> vk.Pipeline {
	viewportState := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	colorBlending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &colorBlendAttachment,
	}

	vertexInputInfo := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	dynamicStates := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamicStatesInfo := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamicStates)),
		pDynamicStates    = &dynamicStates[0],
	}

	pipelineInfo := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &renderInfo,
		stageCount          = u32(len(shaderStages)),
		pStages             = &shaderStages[0],
		pVertexInputState   = &vertexInputInfo,
		pInputAssemblyState = &inputAssembly,
		pViewportState      = &viewportState,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &colorBlending,
		pDepthStencilState  = &depthStencil,
		layout              = pipelineLayout,
		pDynamicState       = &dynamicStatesInfo,
	}

	pipeline: vk.Pipeline

	// TODO: Gracefully handle failure ?
	check(vk.CreateGraphicsPipelines(device, vk.PipelineCache{}, 1, &pipelineInfo, nil, &pipeline))

	return pipeline
}

SetGraphicsPipelineShaders :: proc(
	using config: ^GraphicsPipelineConfig,
	vertexShader, fragmentShader: vk.ShaderModule,
	allocator := context.allocator,
) {
    delete(shaderStages)
    shaderStages = make([dynamic]vk.PipelineShaderStageCreateInfo, allocator)

	vertexShaderInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertexShader,
		pName  = "main",
	}

	append(&shaderStages, vertexShaderInfo)

	fragmentShaderInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragmentShader,
		pName  = "main",
	}

	append(&shaderStages, fragmentShaderInfo)
}


SetGraphicsPipelineInputTopology :: proc(
	using config: ^GraphicsPipelineConfig,
	topology: vk.PrimitiveTopology,
) {
	inputAssembly.topology = topology
	inputAssembly.primitiveRestartEnable = false
}

SetGraphicsPipelinePolygonMode :: proc(
	using config: ^GraphicsPipelineConfig,
	polygonMode: vk.PolygonMode,
) {
	rasterizer.polygonMode = polygonMode
	rasterizer.lineWidth = 1.0
}

SetGraphicsPipelineCullMode :: proc(
	using config: ^GraphicsPipelineConfig,
	cullMode: vk.CullModeFlags,
	frontFace: vk.FrontFace,
) {
	rasterizer.cullMode = cullMode
	rasterizer.frontFace = frontFace
}

DisableGraphicsPipelineMultisampling :: proc(using config: ^GraphicsPipelineConfig) {
	multisampling.sampleShadingEnable = false
	multisampling.rasterizationSamples = {._1}
	multisampling.minSampleShading = 1.0
	multisampling.pSampleMask = nil
	multisampling.alphaToCoverageEnable = false
	multisampling.alphaToOneEnable = false
}

DisableGraphicsPipelineBlending :: proc(using config: ^GraphicsPipelineConfig) {
	colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
	colorBlendAttachment.blendEnable = false
}

SetGraphicsPipelineColorAttachmentFormat :: proc(
	using config: ^GraphicsPipelineConfig,
	format: vk.Format,
) {
	colorAttachmentFormat = format
	renderInfo.colorAttachmentCount = 1
	renderInfo.pColorAttachmentFormats = &colorAttachmentFormat
}

SetGraphicsPipelineDepthFormat :: proc(using config: ^GraphicsPipelineConfig, format: vk.Format) {
	renderInfo.depthAttachmentFormat = format
}

DisableGraphicsPipelineDepthTest :: proc(using config: ^GraphicsPipelineConfig) {
	depthStencil.depthTestEnable = false
	depthStencil.depthWriteEnable = false
	depthStencil.depthCompareOp = .NEVER
	depthStencil.depthBoundsTestEnable = false
	depthStencil.stencilTestEnable = false
	depthStencil.front = vk.StencilOpState{}
	depthStencil.back = vk.StencilOpState{}
	depthStencil.minDepthBounds = 0.0
	depthStencil.maxDepthBounds = 1.0
}

EnableGraphicsPipelineDepthTest :: proc(using config: ^GraphicsPipelineConfig, depthWriteEnable: bool, op: vk.CompareOp) {
	depthStencil.depthTestEnable = true
	depthStencil.depthWriteEnable = b32(depthWriteEnable)
	depthStencil.depthCompareOp = op
	depthStencil.depthBoundsTestEnable = false
	depthStencil.stencilTestEnable = false
	depthStencil.front = vk.StencilOpState{}
	depthStencil.back = vk.StencilOpState{}
	depthStencil.minDepthBounds = 0.0
	depthStencil.maxDepthBounds = 1.0
}
