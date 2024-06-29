package spark

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "shared:odin-imgui/imgui_impl_vulkan"
import vma "shared:odin-vma"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

Context :: struct {
	window:                           glfw.WindowHandle,
	device:                           Device,
	swapchain:                        Swapchain,
	frames:                           [FRAME_OVERLAP]Frame_Data,
	draw_image:                       Image,
	depth_image:                      Image,
	draw_extent:                      vk.Extent2D,
	draw_image_descriptor_pool:       vk.DescriptorPool,
	draw_image_descriptors:           vk.DescriptorSet,
	draw_image_descriptor_layout:     vk.DescriptorSetLayout,
	immediate_context:                Immediate_Context,
	imgui_pool:                       vk.DescriptorPool,
	frame_number:                     int,
	gradient_pipeline_layout:         vk.PipelineLayout,
	compute_effects:                  [dynamic]Compute_Effect,
	current_effect:                   i32,
	mesh_pipeline_layout:             vk.PipelineLayout,
	mesh_pipeline:                    vk.Pipeline,
	test_meshes:                      []Mesh_Asset,
	scene_data:                       Gpu_Scene_Data,
	gpu_scene_data_descriptor_layout: vk.DescriptorSetLayout,
	single_image_descriptor_layout:   vk.DescriptorSetLayout,
	resize_requested:                 bool,
	white_image:                      Image,
	black_image:                      Image,
	grey_image:                       Image,
	error_checkerboard_image:         Image,
	default_sampler_linear:           vk.Sampler,
	default_sampler_nearest:          vk.Sampler,
	raytraced_image_data:             [][4]f32,
	raytraced_data_buffer:            Buffer,
}

Immediate_Context :: struct {
	device:         ^Device,
	fence:          vk.Fence,
	command_buffer: vk.CommandBuffer,
	command_pool:   vk.CommandPool,
}

Deletion_Queue :: struct {
	buffers: [dynamic]Buffer,
	images:  [dynamic]Image,
}

Frame_Data :: struct {
	swapchain_semaphore: vk.Semaphore,
	render_semaphore:    vk.Semaphore,
	render_fence:        vk.Fence,
	command_pool:        vk.CommandPool,
	command_buffer:      vk.CommandBuffer,
	frame_descriptors:   Descriptor_Allocator,
	deletion_queue:      Deletion_Queue,
}

Compute_Push_Constants :: struct {
	data1: glm.vec4,
	data2: glm.vec4,
	data3: glm.vec4,
	data4: glm.vec4,
}

Compute_Effect :: struct {
	name:     string,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
	data:     Compute_Push_Constants,
}

Gpu_Push_Constants :: struct {
	world_matrix:  glm.mat4,
	vertex_buffer: vk.DeviceAddress,
}

Gpu_Scene_Data :: struct {
	view:               glm.mat4,
	proj:               glm.mat4,
	view_proj:          glm.mat4,
	ambient_color:      glm.vec4,
	sunlight_direction: glm.vec4,
	sunlight_color:     glm.vec4,
}

DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"}
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}
FRAME_OVERLAP :: 2

g_ctx: runtime.Context

init_window :: proc(using ctx: ^Context) {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window = glfw.CreateWindow(1024, 768, "Spark", nil, nil)
}

init_vulkan :: proc(using ctx: ^Context) {
	device = init_device(window)

	init_swapchain(device, &swapchain)
	init_draw_image(ctx)
	init_draw_image_descriptors(ctx)

	init_descriptors(ctx)
	init_commands(ctx)
	init_sync_structures(ctx)
	init_pipelines(ctx)

	init_immediate_context(ctx)

	init_default_data(ctx)

	test_meshes = load_gltf(&immediate_context, "models/basicmesh.glb") or_else os.exit(1)

	init_imgui(ctx)

	free_all(context.temp_allocator)
}

deinit_vulkan :: proc(using ctx: ^Context) {
	vk.DeviceWaitIdle(device.device)

	// TODO: Deletion queue

	imgui_impl_vulkan.Shutdown()
	imgui_impl_glfw.Shutdown()
	vk.DestroyDescriptorPool(device.device, imgui_pool, nil)
	im.DestroyContext()

	for mesh in test_meshes {
		delete_mesh_asset(device, mesh)
	}
	delete(test_meshes)

	destroy_immediate_context(immediate_context)

	for effect in compute_effects {
		vk.DestroyPipeline(device.device, effect.pipeline, nil)
	}
	delete(compute_effects)

	vk.DestroyPipeline(device.device, mesh_pipeline, nil)
	vk.DestroyPipelineLayout(device.device, mesh_pipeline_layout, nil)
	vk.DestroyPipelineLayout(device.device, gradient_pipeline_layout, nil)

	for &frame in frames {
		vk.DestroyFence(device.device, frame.render_fence, nil)
		vk.DestroySemaphore(device.device, frame.render_semaphore, nil)
		vk.DestroySemaphore(device.device, frame.swapchain_semaphore, nil)
		vk.DestroyCommandPool(device.device, frame.command_pool, nil)
		destroy_deletion_queue(device, &frame.deletion_queue)
		destroy_descriptor_allocator(frame.frame_descriptors)
	}

	vk.DestroyDescriptorSetLayout(device.device, single_image_descriptor_layout, nil)
	vk.DestroyDescriptorSetLayout(device.device, gpu_scene_data_descriptor_layout, nil)

	vk.DestroyDescriptorPool(device.device, draw_image_descriptor_pool, nil)

	destroy_image(device, white_image)
	destroy_image(device, grey_image)
	destroy_image(device, black_image)
	destroy_image(device, error_checkerboard_image)
	vk.DestroySampler(device.device, default_sampler_linear, nil)
	vk.DestroySampler(device.device, default_sampler_nearest, nil)

	destroy_draw_image_descriptors(ctx)
	destroy_draw_image(ctx)
	destroy_swapchain(device, &swapchain)

	deinit_device(&device)
}

deinit_window :: proc(using ctx: ^Context) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

init_descriptors :: proc(using ctx: ^Context) {
	for &frame in frames {
		frame_sizes := []Descriptor_Pool_Size_Ratio {
			{.STORAGE_IMAGE, 3},
			{.STORAGE_BUFFER, 3},
			{.UNIFORM_BUFFER, 3},
			{.COMBINED_IMAGE_SAMPLER, 4},
		}

		frame.frame_descriptors = create_descriptor_allocator(device, 1000, frame_sizes)
	}

	{
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{binding = 0, descriptorType = .UNIFORM_BUFFER, descriptorCount = 1},
		}

		gpu_scene_data_descriptor_layout = build_descriptor_layout(
			device,
			bindings[:],
			{.VERTEX, .FRAGMENT},
			nil,
			{},
		)
	}

	{
		bindings := [?]vk.DescriptorSetLayoutBinding {
			{binding = 0, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1},
		}

		single_image_descriptor_layout = build_descriptor_layout(
			device,
			bindings[:],
			{.FRAGMENT},
			nil,
			{},
		)
	}
}

init_commands :: proc(using ctx: ^Context) {
	cmd_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(device.queue_indices[.Graphics]),
	}

	for &frame in frames {
		check(vk.CreateCommandPool(device.device, &cmd_pool_info, nil, &frame.command_pool))

		cmd_alloc_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = frame.command_pool,
			commandBufferCount = 1,
			level              = .PRIMARY,
		}

		check(vk.AllocateCommandBuffers(device.device, &cmd_alloc_info, &frame.command_buffer))
	}
}

init_sync_structures :: proc(using ctx: ^Context) {
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	for &frame in frames {
		check(vk.CreateFence(device.device, &fence_info, nil, &frame.render_fence))

		check(vk.CreateSemaphore(device.device, &semaphore_info, nil, &frame.swapchain_semaphore))
		check(vk.CreateSemaphore(device.device, &semaphore_info, nil, &frame.render_semaphore))
	}

}

init_draw_image_descriptors :: proc(using ctx: ^Context) {
	if (draw_image_descriptor_pool == vk.DescriptorPool{}) {
		sizes := [?]Descriptor_Pool_Size_Ratio{{.STORAGE_IMAGE, 1}}
		draw_image_descriptor_pool = create_descriptor_pool(device, 2, sizes[:])
	} else {
		vk.ResetDescriptorPool(device.device, draw_image_descriptor_pool, {})
	}

	if (raytraced_data_buffer != Buffer{}) {
		destroy_buffer(device, raytraced_data_buffer)
		delete(raytraced_image_data)
	}

	raytraced_image_data = make([][4]f32, draw_extent.width * draw_extent.height)

	raytraced_data_buffer = create_buffer(
		ctx.device,
		u64(len(raytraced_image_data) * size_of([4]f32)),
		{.STORAGE_BUFFER, .TRANSFER_SRC},
		.CPU_TO_GPU,
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	bindings := [?]vk.DescriptorSetLayoutBinding {
		{binding = 0, descriptorType = .STORAGE_IMAGE, descriptorCount = 1},
		{binding = 1, descriptorType = .STORAGE_BUFFER, descriptorCount = 1},
	}

	draw_image_descriptor_layout = build_descriptor_layout(
		device,
		bindings[:],
		{.COMPUTE},
		nil,
		{},
	)

	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = draw_image_descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &draw_image_descriptor_layout,
	}

	check(vk.AllocateDescriptorSets(device.device, &allocInfo, &draw_image_descriptors))

	writer: Descriptor_Writer
	write_image_descriptor(&writer, 0, draw_image, {}, .GENERAL, .STORAGE_IMAGE)
	write_buffer_descriptor(
		&writer,
		1,
		raytraced_data_buffer,
		cast(u64)raytraced_data_buffer.allocation_info.size,
		0,
		.STORAGE_BUFFER,
	)
	update_descriptor_set(&writer, device, draw_image_descriptors)
	clear_descriptor_writer(&writer)
}

init_pipelines :: proc(using ctx: ^Context) {
	init_background_pipeline(ctx)
	init_mesh_pipeline(ctx)
}

init_background_pipeline :: proc(using ctx: ^Context) {
	push_constant := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(Compute_Push_Constants),
		stageFlags = {.COMPUTE},
	}

	compute_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &draw_image_descriptor_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_constant,
	}
	check(
		vk.CreatePipelineLayout(
			device.device,
			&compute_layout_info,
			nil,
			&gradient_pipeline_layout,
		),
	)

	gradient_shader :=
		load_shader_module(device, "shaders/bin/gradient.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, gradient_shader, nil)

	gradient := Compute_Effect {
		layout = gradient_pipeline_layout,
		name = "gradient",
		data = {data1 = {1, 0, 0, 1}, data2 = {0, 0, 1, 1}},
	}

	gradient_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = gradient_shader,
		pName  = "main",
	}

	gradient_compute_pipeline_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = gradient_pipeline_layout,
		stage  = gradient_stage_info,
	}

	check(
		vk.CreateComputePipelines(
			device.device,
			vk.PipelineCache{},
			1,
			&gradient_compute_pipeline_info,
			nil,
			&gradient.pipeline,
		),
	)

	append(&compute_effects, gradient)

	sky_shader := load_shader_module(device, "shaders/bin/sky.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, sky_shader, nil)

	sky := Compute_Effect {
		layout = gradient_pipeline_layout,
		name = "sky",
		data = {data1 = {0.1, 0.2, 0.4, 0.97}},
	}

	sky_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = sky_shader,
		pName  = "main",
	}

	sky_compute_pipeline_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = gradient_pipeline_layout,
		stage  = sky_stage_info,
	}

	check(
		vk.CreateComputePipelines(
			device.device,
			vk.PipelineCache{},
			1,
			&sky_compute_pipeline_info,
			nil,
			&sky.pipeline,
		),
	)

	append(&compute_effects, sky)
}

init_mesh_pipeline :: proc(using ctx: ^Context) {
	triangle_vert_shader :=
		load_shader_module(device, "shaders/bin/colored_triangle_mesh.vert.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, triangle_vert_shader, nil)
	triangle_frag_shader :=
		load_shader_module(device, "shaders/bin/tex_image.frag.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, triangle_frag_shader, nil)

	buffer_range := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(Gpu_Push_Constants),
		stageFlags = {.VERTEX},
	}

	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &buffer_range,
		setLayoutCount         = 1,
		pSetLayouts            = &single_image_descriptor_layout,
	}
	check(
		vk.CreatePipelineLayout(device.device, &pipeline_layout_info, nil, &mesh_pipeline_layout),
	)

	pipeline_config := default_graphics_pipeline_config()
	pipeline_config.pipeline_layout = mesh_pipeline_layout
	set_graphics_pipeline_shaders(
		&pipeline_config,
		triangle_vert_shader,
		triangle_frag_shader,
		context.temp_allocator,
	)
	set_graphics_pipeline_input_topology(&pipeline_config, .TRIANGLE_LIST)
	set_graphics_pipeline_polygon_mode(&pipeline_config, .FILL)
	set_graphics_pipeline_cull_mode(&pipeline_config, {.BACK}, .CLOCKWISE)
	disable_graphics_pipeline_multisampling(&pipeline_config)
	enable_graphics_pipeline_depth_test(&pipeline_config, true, .GREATER_OR_EQUAL)
	disable_graphics_pipeline_blending(&pipeline_config)
	set_graphics_pipeline_color_attachment_format(&pipeline_config, draw_image.format)
	set_graphics_pipeline_depth_format(&pipeline_config, depth_image.format)

	mesh_pipeline = build_graphics_pipeline(device, &pipeline_config)
}

init_imgui :: proc(using ctx: ^Context) {
	pool_sizes := [?]vk.DescriptorPoolSize {
		{.SAMPLER, 1000},
		{.COMBINED_IMAGE_SAMPLER, 1000},
		{.SAMPLED_IMAGE, 1000},
		{.STORAGE_IMAGE, 1000},
		{.UNIFORM_TEXEL_BUFFER, 1000},
		{.STORAGE_TEXEL_BUFFER, 1000},
		{.UNIFORM_BUFFER, 1000},
		{.STORAGE_BUFFER, 1000},
		{.UNIFORM_BUFFER_DYNAMIC, 1000},
		{.STORAGE_BUFFER_DYNAMIC, 1000},
		{.INPUT_ATTACHMENT, 1000},
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1000,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = &pool_sizes[0],
	}

	check(vk.CreateDescriptorPool(device.device, &pool_info, nil, &imgui_pool))

	im.CreateContext()

	imgui_impl_glfw.InitForVulkan(window, true)

	init_info := imgui_impl_vulkan.InitInfo {
		Instance              = device.instance,
		PhysicalDevice        = device.gpu,
		Device                = device.device,
		Queue                 = device.queues[.Graphics],
		DescriptorPool        = imgui_pool,
		MinImageCount         = 3,
		ImageCount            = 3,
		UseDynamicRendering   = true,
		ColorAttachmentFormat = swapchain.format.format,
		MSAASamples           = {._1},
	}

	imgui_impl_vulkan.LoadFunctions(
		proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr((cast(^vk.Instance)user_data)^, function_name)
		},
		&device.instance,
	)

	imgui_impl_vulkan.Init(&init_info, 0)
	imgui_impl_vulkan.CreateFontsTexture()
}

draw :: proc(using ctx: ^Context) {
	frame := &frames[frame_number % FRAME_OVERLAP]
	check(vk.WaitForFences(device.device, 1, &frame.render_fence, true, 1000000000))

	flush_deletion_queue(device, &frame.deletion_queue)

	clear_descriptor_allocator_pools(&frame.frame_descriptors)

	check(vk.ResetFences(device.device, 1, &frame.render_fence))

	swapchain_image_index: u32
	res := vk.AcquireNextImageKHR(
		device.device,
		swapchain.swapchain,
		1000000000,
		frame.swapchain_semaphore,
		vk.Fence{},
		&swapchain_image_index,
	)

	if res == .ERROR_OUT_OF_DATE_KHR {
		resize_requested = true
		return
	}

	draw_extent = {draw_image.extent.width, draw_image.extent.height}

	cmd := frame.command_buffer
	check(vk.ResetCommandBuffer(cmd, {.RELEASE_RESOURCES}))

	cmd_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	transition_image(cmd, draw_image.image, .UNDEFINED, .GENERAL)

	draw_background(cmd, ctx)

	transition_image(cmd, draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	transition_image(cmd, depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	//draw_geometry(cmd, ctx)

	transition_image(cmd, draw_image.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	transition_image(
		cmd,
		swapchain.images[swapchain_image_index],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
	)

	blit_image(
		cmd,
		draw_image.image,
		swapchain.images[swapchain_image_index],
		draw_extent,
		swapchain.extent,
	)

	transition_image(
		cmd,
		swapchain.images[swapchain_image_index],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	draw_imgui(ctx, cmd, swapchain.image_views[swapchain_image_index])

	transition_image(
		cmd,
		swapchain.images[swapchain_image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	check(vk.EndCommandBuffer(cmd))

	cmdInfo := command_buffer_submit_info(cmd)
	waitInfo := semaphore_submit_info({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchain_semaphore)
	signalInfo := semaphore_submit_info({.ALL_GRAPHICS}, frame.render_semaphore)
	submit := submit_info(&cmdInfo, &waitInfo, &signalInfo)

	check(vk.QueueSubmit2(device.queues[.Graphics], 1, &submit, frame.render_fence))

	presentInfo := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.swapchain,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.render_semaphore,
		pImageIndices      = &swapchain_image_index,
	}

	res = vk.QueuePresentKHR(device.queues[.Graphics], &presentInfo)

	if res == .ERROR_OUT_OF_DATE_KHR {
		resize_requested = true
		return
	}

	frame_number += 1
}

draw_background :: proc(cmd: vk.CommandBuffer, using ctx: ^Context) {
	effect := compute_effects[current_effect]

	mem.copy(
		raytraced_data_buffer.allocation_info.pMappedData,
		raw_data(raytraced_image_data),
		len(raytraced_image_data) * size_of([4]f32),
	)

	vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, effect.layout, 0, 1, &draw_image_descriptors, 0, nil)

	vk.CmdPushConstants(
		cmd,
		effect.layout,
		{.COMPUTE},
		0,
		size_of(Compute_Push_Constants),
		&compute_effects[current_effect].data,
	)

	vk.CmdDispatch(cmd, u32(draw_extent.width / 16.0) + 1, u32(draw_extent.height / 16.0) + 1, 1)
}

draw_geometry :: proc(cmd: vk.CommandBuffer, using ctx: ^Context) {
	frame := &frames[frame_number % FRAME_OVERLAP]

	// TODO: Move this inside the frame data, no need to destroy / create it every frame
	gpu_scene_buffer := create_buffer(
		device,
		size_of(Gpu_Scene_Data),
		{.UNIFORM_BUFFER},
		.CPU_TO_GPU,
		{.DEVICE_LOCAL},
	)

	append(&frame.deletion_queue.buffers, gpu_scene_buffer)

	scene_uniform_data := cast(^Gpu_Scene_Data)gpu_scene_buffer.allocation_info.pMappedData
	scene_uniform_data^ = scene_data

	global_descriptor := allocate_descriptor_set(
		&frame.frame_descriptors,
		gpu_scene_data_descriptor_layout,
	)

	writer: Descriptor_Writer
	write_buffer_descriptor(
		&writer,
		0,
		gpu_scene_buffer,
		size_of(Gpu_Scene_Data),
		0,
		.UNIFORM_BUFFER,
	)
	update_descriptor_set(&writer, device, global_descriptor)
	clear_descriptor_writer(&writer)

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = draw_image.image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	depth_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = depth_image.image_view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {depthStencil = {depth = 0.0}},
	}

	render_area := vk.Rect2D {
		extent = draw_extent,
	}

	render_info := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = render_area,
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment,
		pDepthAttachment     = &depth_attachment,
	}

	vk.CmdBeginRendering(cmd, &render_info)

	vk.CmdBindPipeline(cmd, .GRAPHICS, mesh_pipeline)

	image_set := allocate_descriptor_set(&frame.frame_descriptors, single_image_descriptor_layout)
	{
		writer: Descriptor_Writer
		write_image_descriptor(
			&writer,
			0,
			error_checkerboard_image,
			default_sampler_nearest,
			.SHADER_READ_ONLY_OPTIMAL,
			.COMBINED_IMAGE_SAMPLER,
		)
		update_descriptor_set(&writer, device, image_set)
		clear_descriptor_writer(&writer)
	}

	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, mesh_pipeline_layout, 0, 1, &image_set, 0, nil)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(draw_extent.width),
		height   = f32(draw_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = draw_extent,
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	push_constants: Gpu_Push_Constants

	view := glm.mat4LookAt({0, 0, -5}, {0, 0, 0}, {0, 1, 0})
	proj := glm.mat4Perspective(
		glm.radians(f32(70)),
		f32(draw_extent.width) / f32(draw_extent.height),
		0.1,
		10000,
	)

	proj[1][1] *= -1

	mesh := test_meshes[2]

	push_constants.vertex_buffer = mesh.mesh_buffers.vertex_buffer_address
	push_constants.world_matrix = proj * view
	vk.CmdPushConstants(
		cmd,
		mesh_pipeline_layout,
		{.VERTEX},
		0,
		size_of(Gpu_Push_Constants),
		&push_constants,
	)
	vk.CmdBindIndexBuffer(cmd, mesh.mesh_buffers.index_buffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(cmd, mesh.surfaces[0].count, 1, mesh.surfaces[0].start_index, 0, 0)

	vk.CmdEndRendering(cmd)
}

draw_imgui :: proc(using ctx: ^Context, cmd: vk.CommandBuffer, target_image_view: vk.ImageView) {
	color_attachment_info := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = target_image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	render_area := vk.Rect2D {
		extent = swapchain.extent,
	}

	render_info := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = render_area,
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_info,
	}

	vk.CmdBeginRendering(cmd, &render_info)

	imgui_impl_vulkan.RenderDrawData(im.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}

immediate_submit :: proc(
	using ctx: ^Immediate_Context,
	fn: proc(_: ^Immediate_Context, _: vk.CommandBuffer),
) {
	check(vk.ResetFences(device.device, 1, &fence))
	check(vk.ResetCommandBuffer(command_buffer, vk.CommandBufferResetFlags{}))

	cmd := command_buffer

	cmd_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	fn(ctx, cmd)

	check(vk.EndCommandBuffer(cmd))

	cmdInfo := command_buffer_submit_info(cmd)
	submit := submit_info(&cmdInfo, nil, nil)

	check(vk.QueueSubmit2(device.queues[.Graphics], 1, &submit, fence))
	check(vk.WaitForFences(device.device, 1, &fence, true, 9999999999))
}

upload_mesh :: proc(
	using ctx: ^Immediate_Context,
	indices: []u32,
	vertices: []Vertex,
) -> Gpu_Mesh_Buffers {
	vertex_buffer_size := u64(len(vertices) * size_of(Vertex))
	index_buffer_size := u64(len(indices) * size_of(u32))

	new_surface: Gpu_Mesh_Buffers

	new_surface.vertex_buffer = create_buffer(
		device^,
		vertex_buffer_size,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
		{.DEVICE_LOCAL},
	)

	device_address_info := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = new_surface.vertex_buffer.buffer,
	}

	new_surface.vertex_buffer_address = vk.GetBufferDeviceAddress(
		device.device,
		&device_address_info,
	)

	new_surface.index_buffer = create_buffer(
		device^,
		index_buffer_size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.GPU_ONLY,
		{.DEVICE_LOCAL},
	)

	staging_buffer := create_buffer(
		device^,
		vertex_buffer_size + index_buffer_size,
		{.TRANSFER_SRC},
		.CPU_ONLY,
		{.DEVICE_LOCAL},
	)

	data := staging_buffer.allocation_info.pMappedData

	mem.copy(data, raw_data(vertices), int(vertex_buffer_size))
	mem.copy(
		mem.ptr_offset(cast(^byte)data, vertex_buffer_size),
		raw_data(indices),
		int(index_buffer_size),
	)

	Temp_Data :: struct {
		vertex_buffer_size: u64,
		index_buffer_size:  u64,
		src_buffer:         vk.Buffer,
		dst_vertex_buffer:  vk.Buffer,
		dst_index_buffer:   vk.Buffer,
	}

	temp_data := Temp_Data {
		vertex_buffer_size = vertex_buffer_size,
		index_buffer_size  = index_buffer_size,
		src_buffer         = staging_buffer.buffer,
		dst_vertex_buffer  = new_surface.vertex_buffer.buffer,
		dst_index_buffer   = new_surface.index_buffer.buffer,
	}

	context.user_ptr = &temp_data

	submit_fn := proc(ctx: ^Immediate_Context, cmd: vk.CommandBuffer) {
		data := (cast(^Temp_Data)context.user_ptr)^
		vertex_copy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = 0,
			size      = cast(vk.DeviceSize)data.vertex_buffer_size,
		}
		vk.CmdCopyBuffer(cmd, data.src_buffer, data.dst_vertex_buffer, 1, &vertex_copy)

		indexCopy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = cast(vk.DeviceSize)data.vertex_buffer_size,
			size      = cast(vk.DeviceSize)data.index_buffer_size,
		}
		vk.CmdCopyBuffer(cmd, data.src_buffer, data.dst_index_buffer, 1, &indexCopy)
	}

	immediate_submit(ctx, submit_fn)

	destroy_buffer(device^, staging_buffer)

	return new_surface
}

init_default_data :: proc(using ctx: ^Context) {
	white: u32 = 0xFFFFFFFF
	white_image = create_image_with_data(
		&immediate_context,
		&white,
		vk.Extent3D{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	grey: u32 = 0xAAAAAAAA
	grey_image = create_image_with_data(
		&immediate_context,
		&grey,
		vk.Extent3D{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	black: u32 = 0x00000000
	black_image = create_image_with_data(
		&immediate_context,
		&black,
		vk.Extent3D{1, 1, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	magenta: u32 = 0xFF00FFFF
	pixels: [16 * 16]u32 = ---

	for y := 0; y < 16; y += 1 {
		for x := 0; x < 16; x += 1 {
			color := magenta if ((x % 2) ~ (y % 2)) == 1 else black
			pixels[y * 16 + x] = color
		}
	}

	error_checkerboard_image = create_image_with_data(
		&immediate_context,
		raw_data(pixels[:]),
		vk.Extent3D{16, 16, 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	nearest_sampler_info := vk.SamplerCreateInfo {
		sType     = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .NEAREST,
	}

	check(vk.CreateSampler(device.device, &nearest_sampler_info, nil, &default_sampler_nearest))

	linear_sampler_info := vk.SamplerCreateInfo {
		sType     = .SAMPLER_CREATE_INFO,
		magFilter = .LINEAR,
		minFilter = .LINEAR,
	}

	check(vk.CreateSampler(device.device, &linear_sampler_info, nil, &default_sampler_linear))
}

destroy_draw_image :: proc(using ctx: ^Context) {
	// DestroyFramebuffer
	destroy_image(device, depth_image)
	destroy_image(device, draw_image)
}

destroy_draw_image_descriptors :: proc(using ctx: ^Context) {
	vk.DestroyDescriptorSetLayout(device.device, draw_image_descriptor_layout, nil)
}

resize_draw_image :: proc(using ctx: ^Context) {
	destroy_draw_image(ctx)
	init_draw_image(ctx)

	destroy_draw_image_descriptors(ctx)
	init_draw_image_descriptors(ctx)
}

init_draw_image :: proc(using ctx: ^Context) {
	// TODO: Store the window extents
	draw_image_extent := vk.Extent3D{swapchain.extent.width, swapchain.extent.height, 1}
	draw_image_usage := vk.ImageUsageFlags {
		.TRANSFER_SRC,
		.TRANSFER_DST,
		.STORAGE,
		.COLOR_ATTACHMENT,
	}

	draw_image = create_image(device, draw_image_extent, .R16G16B16A16_SFLOAT, draw_image_usage)
	draw_extent = {draw_image_extent.width, draw_image_extent.height}

	depth_image_usage := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

	depth_image = create_image(device, draw_image_extent, .D32_SFLOAT, depth_image_usage)
}

init_immediate_context :: proc(using ctx: ^Context) {
	immediate_context.device = &device

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	check(vk.CreateFence(device.device, &fence_info, nil, &immediate_context.fence))

	cmd_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(device.queue_indices[.Graphics]),
	}

	check(
		vk.CreateCommandPool(device.device, &cmd_pool_info, nil, &immediate_context.command_pool),
	)

	cmd_alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = immediate_context.command_pool,
		commandBufferCount = 1,
		level              = .PRIMARY,
	}

	check(
		vk.AllocateCommandBuffers(
			device.device,
			&cmd_alloc_info,
			&immediate_context.command_buffer,
		),
	)
}

destroy_immediate_context :: proc(ctx: Immediate_Context) {
	vk.DestroyCommandPool(ctx.device.device, ctx.command_pool, nil)
	vk.DestroyFence(ctx.device.device, ctx.fence, nil)
}

flush_deletion_queue :: proc(device: Device, using queue: ^Deletion_Queue) {
	for buffer in buffers {
		destroy_buffer(device, buffer)
	}
	clear(&buffers)

	for image in images {
		destroy_image(device, image)
	}
	clear(&images)
}

destroy_deletion_queue :: proc(device: Device, using queue: ^Deletion_Queue) {
	flush_deletion_queue(device, queue)
	delete(buffers)
	delete(images)
}

resize_if_necessary :: proc(using ctx: ^Context) -> bool {
	if resize_requested {
		resize_swapchain(device, &swapchain)
		resize_draw_image(ctx)
		resize_requested = false
        return true
	}

    return false
}
