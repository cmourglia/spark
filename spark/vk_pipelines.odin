package spark

import "core:log"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

load_shader_module :: proc(device: vk.Device, filepath: string) -> (vk.ShaderModule, b32) {
	shader_module: vk.ShaderModule

	content, ok := os.read_entire_file(filepath, context.temp_allocator)
	if !ok {
		log.errorf("Could not read file '%s'\n", filepath)
		return shader_module, false
	}

	code := slice.reinterpret([]u32, content)

	shader_module_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(content),
		pCode    = raw_data(code),
	}

	check(vk.CreateShaderModule(device, &shader_module_info, nil, &shader_module))

	return shader_module, true
}

Graphics_Pipeline_Config :: struct {
	shader_stages:           [dynamic]vk.PipelineShaderStageCreateInfo,
	input_assembly:          vk.PipelineInputAssemblyStateCreateInfo,
	rasterizer:              vk.PipelineRasterizationStateCreateInfo,
	color_blend_attachment:  vk.PipelineColorBlendAttachmentState,
	multisampling:           vk.PipelineMultisampleStateCreateInfo,
	depth_stencil:           vk.PipelineDepthStencilStateCreateInfo,
	render_info:             vk.PipelineRenderingCreateInfo,
	pipeline_layout:         vk.PipelineLayout,
	color_attachment_format: vk.Format,
}

default_graphics_pipeline_config :: proc() -> Graphics_Pipeline_Config {
	config := Graphics_Pipeline_Config {
		input_assembly = {sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO},
		rasterizer = {sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO},
		multisampling = {sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO},
		depth_stencil = {sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO},
		render_info = {sType = .PIPELINE_RENDERING_CREATE_INFO},
	}

	return config
}


build_graphics_pipeline :: proc(
	device: vk.Device,
	using config: ^Graphics_Pipeline_Config,
) -> vk.Pipeline {
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_states_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = &dynamic_states[0],
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &render_info,
		stageCount          = u32(len(shader_stages)),
		pStages             = &shader_stages[0],
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDepthStencilState  = &depth_stencil,
		layout              = pipeline_layout,
		pDynamicState       = &dynamic_states_info,
	}

	pipeline: vk.Pipeline

	// TODO: Gracefully handle failure ?
	check(
		vk.CreateGraphicsPipelines(device, vk.PipelineCache{}, 1, &pipeline_info, nil, &pipeline),
	)

	return pipeline
}

set_graphics_pipeline_shaders :: proc(
	using config: ^Graphics_Pipeline_Config,
	vertex_shader, fragment_shader: vk.ShaderModule,
	allocator := context.allocator,
) {
	delete(shader_stages)
	shader_stages = make([dynamic]vk.PipelineShaderStageCreateInfo, allocator)

	vertex_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vertex_shader,
		pName  = "main",
	}

	append(&shader_stages, vertex_shader_info)

	fragment_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = fragment_shader,
		pName  = "main",
	}

	append(&shader_stages, fragment_shader_info)
}


set_graphics_pipeline_input_topology :: proc(
	using config: ^Graphics_Pipeline_Config,
	topology: vk.PrimitiveTopology,
) {
	input_assembly.topology = topology
	input_assembly.primitiveRestartEnable = false
}

set_graphics_pipeline_polygon_mode :: proc(
	using config: ^Graphics_Pipeline_Config,
	polygon_mode: vk.PolygonMode,
) {
	rasterizer.polygonMode = polygon_mode
	rasterizer.lineWidth = 1.0
}

set_graphics_pipeline_cull_mode :: proc(
	using config: ^Graphics_Pipeline_Config,
	cull_mode: vk.CullModeFlags,
	front_face: vk.FrontFace,
) {
	rasterizer.cullMode = cull_mode
	rasterizer.frontFace = front_face
}

disable_graphics_pipeline_multisampling :: proc(using config: ^Graphics_Pipeline_Config) {
	multisampling.sampleShadingEnable = false
	multisampling.rasterizationSamples = {._1}
	multisampling.minSampleShading = 1.0
	multisampling.pSampleMask = nil
	multisampling.alphaToCoverageEnable = false
	multisampling.alphaToOneEnable = false
}

disable_graphics_pipeline_blending :: proc(using config: ^Graphics_Pipeline_Config) {
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = false
}

enable_graphics_pipeline_additive_blending :: proc(using config: ^Graphics_Pipeline_Config) {
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = true
	color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstColorBlendFactor = .ONE
	color_blend_attachment.colorBlendOp = .ADD
	color_blend_attachment.srcAlphaBlendFactor = .ONE
	color_blend_attachment.dstAlphaBlendFactor = .ZERO
	color_blend_attachment.alphaBlendOp = .ADD
}

enable_graphics_pipeline_alpha_blending :: proc(using config: ^Graphics_Pipeline_Config) {
	color_blend_attachment.colorWriteMask = {.R, .G, .B, .A}
	color_blend_attachment.blendEnable = true
	color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA
	color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	color_blend_attachment.colorBlendOp = .ADD
	color_blend_attachment.srcAlphaBlendFactor = .ONE
	color_blend_attachment.dstAlphaBlendFactor = .ZERO
	color_blend_attachment.alphaBlendOp = .ADD
}

set_graphics_pipeline_color_attachment_format :: proc(
	using config: ^Graphics_Pipeline_Config,
	format: vk.Format,
) {
	color_attachment_format = format
	render_info.colorAttachmentCount = 1
	render_info.pColorAttachmentFormats = &color_attachment_format
}

set_graphics_pipeline_depth_format :: proc(
	using config: ^Graphics_Pipeline_Config,
	format: vk.Format,
) {
	render_info.depthAttachmentFormat = format
}

disable_graphics_pipeline_depth_test :: proc(using config: ^Graphics_Pipeline_Config) {
	depth_stencil.depthTestEnable = false
	depth_stencil.depthWriteEnable = false
	depth_stencil.depthCompareOp = .NEVER
	depth_stencil.depthBoundsTestEnable = false
	depth_stencil.stencilTestEnable = false
	depth_stencil.front = vk.StencilOpState{}
	depth_stencil.back = vk.StencilOpState{}
	depth_stencil.minDepthBounds = 0.0
	depth_stencil.maxDepthBounds = 1.0
}

enable_graphics_pipeline_depth_test :: proc(
	using config: ^Graphics_Pipeline_Config,
	depth_write_enable: bool,
	op: vk.CompareOp,
) {
	depth_stencil.depthTestEnable = true
	depth_stencil.depthWriteEnable = b32(depth_write_enable)
	depth_stencil.depthCompareOp = op
	depth_stencil.depthBoundsTestEnable = false
	depth_stencil.stencilTestEnable = false
	depth_stencil.front = vk.StencilOpState{}
	depth_stencil.back = vk.StencilOpState{}
	depth_stencil.minDepthBounds = 0.0
	depth_stencil.maxDepthBounds = 1.0
}
