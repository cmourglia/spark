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
	window:                    glfw.WindowHandle,
	device:                    Device,
	swapchain:                 Swapchain,
	frames:                    [FRAME_OVERLAP]FrameData,
	drawImage:                 Image,
	depthImage:                Image,
	drawExtent:                vk.Extent2D,
	drawImageDescriptorPool:   vk.DescriptorPool,
	drawImageDescriptors:      vk.DescriptorSet,
	drawImageDescriptorLayout: vk.DescriptorSetLayout,
	immedateContext:           ImmediateContext,
	imguiPool:                 vk.DescriptorPool,
	frameNumber:               int,
	gradientPipelineLayout:    vk.PipelineLayout,
	computeEffects:            [dynamic]ComputeEffect,
	currentEffect:             i32,
	meshPipelineLayout:        vk.PipelineLayout,
	meshPipeline:              vk.Pipeline,
	testMeshes:                []MeshAsset,
	resizeRequested:           bool,
}

ImmediateContext :: struct {
	device:        ^Device,
	fence:         vk.Fence,
	commandBuffer: vk.CommandBuffer,
	commandPool:   vk.CommandPool,
}

FrameData :: struct {
	commandPool:        vk.CommandPool,
	commandBuffer:      vk.CommandBuffer,
	swapchainSemaphore: vk.Semaphore,
	renderSemaphore:    vk.Semaphore,
	renderFence:        vk.Fence,
}

ComputePushConstants :: struct {
	data1: glm.vec4,
	data2: glm.vec4,
	data3: glm.vec4,
	data4: glm.vec4,
}

ComputeEffect :: struct {
	name:     string,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
	data:     ComputePushConstants,
}

GpuPushConstants :: struct {
	worldMatrix:  glm.mat4,
	vertexBuffer: vk.DeviceAddress,
}

DEVICE_EXTENSIONS := [?]cstring{"VK_KHR_swapchain"}
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}
FRAME_OVERLAP :: 2

g_ctx: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	g_ctx = context

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	Run()

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %m\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}

Run :: proc() {
	ctx := Context{}

	InitWindow(&ctx)
	defer DeinitWindow(&ctx)

	InitVulkan(&ctx)
	defer DeinitVulkan(&ctx)

	MainLoop(&ctx)
}

InitWindow :: proc(using ctx: ^Context) {
	glfw.Init()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window = glfw.CreateWindow(1024, 768, "Spark", nil, nil)
}

InitVulkan :: proc(using ctx: ^Context) {
	device = InitDevice(window)

	InitSwapchain(device, &swapchain)
	InitDrawImage(ctx)
	InitDrawImageDescriptors(ctx)

	InitCommands(ctx)
	InitSyncStructures(ctx)
	InitPipelines(ctx)

	InitImmediateContext(ctx)

	InitDefaultData(ctx)

	testMeshes = LoadGltf(&immedateContext, "models/basicmesh.glb") or_else os.exit(1)

	InitImgui(ctx)

	free_all(context.temp_allocator)
}

DeinitVulkan :: proc(using ctx: ^Context) {
	vk.DeviceWaitIdle(device.device)

	// TODO: Deletion queue

	imgui_impl_vulkan.Shutdown()
	imgui_impl_glfw.Shutdown()
	vk.DestroyDescriptorPool(device.device, imguiPool, nil)
	im.DestroyContext()

	for mesh in testMeshes {
		DeleteMeshAsset(device, mesh)
	}
	delete(testMeshes)

	DestroyImmediateContext(immedateContext)

	for effect in computeEffects {
		vk.DestroyPipeline(device.device, effect.pipeline, nil)
	}
	delete(computeEffects)

	vk.DestroyPipeline(device.device, meshPipeline, nil)
	vk.DestroyPipelineLayout(device.device, meshPipelineLayout, nil)
	vk.DestroyPipelineLayout(device.device, gradientPipelineLayout, nil)

	for frame in frames {
		vk.DestroyFence(device.device, frame.renderFence, nil)
		vk.DestroySemaphore(device.device, frame.renderSemaphore, nil)
		vk.DestroySemaphore(device.device, frame.swapchainSemaphore, nil)
		vk.DestroyCommandPool(device.device, frame.commandPool, nil)
	}

	vk.DestroyDescriptorPool(device.device, drawImageDescriptorPool, nil)

	DestroyDrawImageDescriptors(ctx)
	DestroyDrawImage(ctx)
	DestroySwapchain(device, &swapchain)

	DeinitDevice(&device)
}

DeinitWindow :: proc(using ctx: ^Context) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

MainLoop :: proc(using ctx: ^Context) {
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		if resizeRequested {
			ResizeSwapchain(device, &swapchain)
			ResizeDrawImage(ctx)
			resizeRequested = false
		}

		imgui_impl_vulkan.NewFrame()
		imgui_impl_glfw.NewFrame()

		im.NewFrame()

		if im.Begin("background") {
			effect := &computeEffects[currentEffect]

			im.Text("Selected effect: ", effect.name)

			im.SliderInt("Effect index", &currentEffect, 0, i32(len(computeEffects) - 1))

			im.InputFloat4("data1", cast(^[4]f32)&effect.data.data1)
			im.InputFloat4("data2", cast(^[4]f32)&effect.data.data2)
			im.InputFloat4("data3", cast(^[4]f32)&effect.data.data3)
			im.InputFloat4("data4", cast(^[4]f32)&effect.data.data4)
		}
		im.End()

		im.Render()

		Draw(ctx)
	}
}

ChooseSwapchainFormat :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SNORM && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	return formats[0]
}

ChooseSwapchainPresentMode :: proc(presentModes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// TODO: Change this at some point
	//for mode in presentModes {
	//	if mode == .MAILBOX {
	//		return mode
	//	}
	//}

	return .FIFO
}

InitCommands :: proc(using ctx: ^Context) {
	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(device.queueIndices[.Graphics]),
	}

	for &frame in frames {
		check(vk.CreateCommandPool(device.device, &cmdPoolInfo, nil, &frame.commandPool))

		cmdAllocInfo := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = frame.commandPool,
			commandBufferCount = 1,
			level              = .PRIMARY,
		}

		check(vk.AllocateCommandBuffers(device.device, &cmdAllocInfo, &frame.commandBuffer))
	}
}

InitSyncStructures :: proc(using ctx: ^Context) {
	fenceInfo := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	semaphoreInfo := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	for &frame in frames {
		check(vk.CreateFence(device.device, &fenceInfo, nil, &frame.renderFence))

		check(vk.CreateSemaphore(device.device, &semaphoreInfo, nil, &frame.swapchainSemaphore))
		check(vk.CreateSemaphore(device.device, &semaphoreInfo, nil, &frame.renderSemaphore))
	}

}

InitDrawImageDescriptors :: proc(using ctx: ^Context) {
	if (drawImageDescriptorPool == vk.DescriptorPool{}) {
		sizes := [?]DescriptorPoolSizeRatio{{.STORAGE_IMAGE, 1}}
		drawImageDescriptorPool = CreateDescriptorPool(device.device, 2, sizes[:])
	} else {
		vk.ResetDescriptorPool(device.device, drawImageDescriptorPool, {})
	}

	bindings := [?]vk.DescriptorSetLayoutBinding {
		{binding = 0, descriptorType = .STORAGE_IMAGE, descriptorCount = 1},
	}

	drawImageDescriptorLayout = BuildDescriptorLayout(
		device.device,
		bindings[:],
		{.COMPUTE},
		nil,
		vk.DescriptorSetLayoutCreateFlags{},
	)

	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = drawImageDescriptorPool,
		descriptorSetCount = 1,
		pSetLayouts        = &drawImageDescriptorLayout,
	}

	check(vk.AllocateDescriptorSets(device.device, &allocInfo, &drawImageDescriptors))

	imgInfo := vk.DescriptorImageInfo {
		imageLayout = .GENERAL,
		imageView   = drawImage.imageView,
	}

	drawImageWrite := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = 0,
		dstSet          = drawImageDescriptors,
		descriptorCount = 1,
		descriptorType  = .STORAGE_IMAGE,
		pImageInfo      = &imgInfo,
	}

	vk.UpdateDescriptorSets(device.device, 1, &drawImageWrite, 0, nil)
}

InitPipelines :: proc(using ctx: ^Context) {
	InitBackgroundPipeline(ctx)
	InitMeshPipeline(ctx)
}

InitBackgroundPipeline :: proc(using ctx: ^Context) {
	pushConstant := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(ComputePushConstants),
		stageFlags = {.COMPUTE},
	}

	computeLayoutInfo := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &drawImageDescriptorLayout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pushConstant,
	}
	check(vk.CreatePipelineLayout(device.device, &computeLayoutInfo, nil, &gradientPipelineLayout))

	gradientShader :=
		LoadShaderModule(device.device, "shaders/bin/gradient_color.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, gradientShader, nil)

	gradient := ComputeEffect {
		layout = gradientPipelineLayout,
		name = "gradient",
		data = {data1 = {1, 0, 0, 1}, data2 = {0, 0, 1, 1}},
	}

	gradientStageInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = gradientShader,
		pName  = "main",
	}

	gradientComputePipelineInfo := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = gradientPipelineLayout,
		stage  = gradientStageInfo,
	}

	check(
		vk.CreateComputePipelines(
			device.device,
			vk.PipelineCache{},
			1,
			&gradientComputePipelineInfo,
			nil,
			&gradient.pipeline,
		),
	)

	append(&computeEffects, gradient)

	skyShader := LoadShaderModule(device.device, "shaders/bin/sky.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, skyShader, nil)

	sky := ComputeEffect {
		layout = gradientPipelineLayout,
		name = "sky",
		data = {data1 = {0.1, 0.2, 0.4, 0.97}},
	}

	skyStageInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = skyShader,
		pName  = "main",
	}

	skyComputePipelineInfo := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = gradientPipelineLayout,
		stage  = skyStageInfo,
	}

	check(
		vk.CreateComputePipelines(
			device.device,
			vk.PipelineCache{},
			1,
			&skyComputePipelineInfo,
			nil,
			&sky.pipeline,
		),
	)

	append(&computeEffects, sky)
}

InitMeshPipeline :: proc(using ctx: ^Context) {
	triangleVertShader :=
		LoadShaderModule(
			device.device,
			"shaders/bin/colored_triangle_mesh.vert.spv",
		) or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, triangleVertShader, nil)
	triangleFragShader :=
		LoadShaderModule(device.device, "shaders/bin/colored_triangle.frag.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device.device, triangleFragShader, nil)

	bufferRange := vk.PushConstantRange {
		offset     = 0,
		size       = size_of(GpuPushConstants),
		stageFlags = {.VERTEX},
	}

	pipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &bufferRange,
	}
	check(vk.CreatePipelineLayout(device.device, &pipelineLayoutInfo, nil, &meshPipelineLayout))

	pipelineConfig := DefaultGraphicsPipelineConfig()
	pipelineConfig.pipelineLayout = meshPipelineLayout
	SetGraphicsPipelineShaders(
		&pipelineConfig,
		triangleVertShader,
		triangleFragShader,
		context.temp_allocator,
	)
	SetGraphicsPipelineInputTopology(&pipelineConfig, .TRIANGLE_LIST)
	SetGraphicsPipelinePolygonMode(&pipelineConfig, .FILL)
	SetGraphicsPipelineCullMode(&pipelineConfig, {.BACK}, .CLOCKWISE)
	DisableGraphicsPipelineMultisampling(&pipelineConfig)
	EnableGraphicsPipelineDepthTest(&pipelineConfig, true, .GREATER_OR_EQUAL)
	DisableGraphicsPipelineBlending(&pipelineConfig)
	SetGraphicsPipelineColorAttachmentFormat(&pipelineConfig, drawImage.format)
	SetGraphicsPipelineDepthFormat(&pipelineConfig, depthImage.format)

	meshPipeline = BuildGraphicsPipeline(device.device, &pipelineConfig)
}

InitImgui :: proc(using ctx: ^Context) {
	poolSizes := [?]vk.DescriptorPoolSize {
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

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1000,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = &poolSizes[0],
	}

	check(vk.CreateDescriptorPool(device.device, &poolInfo, nil, &imguiPool))

	im.CreateContext()

	imgui_impl_glfw.InitForVulkan(window, true)

	initInfo := imgui_impl_vulkan.InitInfo {
		Instance              = device.instance,
		PhysicalDevice        = device.gpu,
		Device                = device.device,
		Queue                 = device.queues[.Graphics],
		DescriptorPool        = imguiPool,
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

	imgui_impl_vulkan.Init(&initInfo, 0)
	imgui_impl_vulkan.CreateFontsTexture()
}

Draw :: proc(using ctx: ^Context) {
	frame := frames[frameNumber % FRAME_OVERLAP]
	check(vk.WaitForFences(device.device, 1, &frame.renderFence, true, 1000000000))
	check(vk.ResetFences(device.device, 1, &frame.renderFence))

	swapchainImageIndex: u32
	res := vk.AcquireNextImageKHR(
		device.device,
		swapchain.swapchain,
		1000000000,
		frame.swapchainSemaphore,
		vk.Fence{},
		&swapchainImageIndex,
	)

	if res == .ERROR_OUT_OF_DATE_KHR {
		resizeRequested = true
		return
	}

	drawExtent = {drawImage.extent.width, drawImage.extent.height}

	cmd := frame.commandBuffer
	check(vk.ResetCommandBuffer(cmd, {.RELEASE_RESOURCES}))

	cmdBeginInfo := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cmdBeginInfo))

	TransitionImage(cmd, drawImage.image, .UNDEFINED, .GENERAL)

	DrawBackground(cmd, ctx)

	TransitionImage(cmd, drawImage.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	TransitionImage(cmd, depthImage.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	DrawGeometry(cmd, ctx)

	TransitionImage(cmd, drawImage.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL)
	TransitionImage(cmd, swapchain.images[swapchainImageIndex], .UNDEFINED, .TRANSFER_DST_OPTIMAL)

	BlitImage(
		cmd,
		drawImage.image,
		swapchain.images[swapchainImageIndex],
		drawExtent,
		swapchain.extent,
	)

	TransitionImage(
		cmd,
		swapchain.images[swapchainImageIndex],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	DrawImgui(ctx, cmd, swapchain.imageViews[swapchainImageIndex])

	TransitionImage(
		cmd,
		swapchain.images[swapchainImageIndex],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	check(vk.EndCommandBuffer(cmd))

	cmdInfo := CommandBufferSubmitInfo(cmd)
	waitInfo := SemaphoreSubmitInfo({.COLOR_ATTACHMENT_OUTPUT_KHR}, frame.swapchainSemaphore)
	signalInfo := SemaphoreSubmitInfo({.ALL_GRAPHICS}, frame.renderSemaphore)
	submit := SubmitInfo(&cmdInfo, &waitInfo, &signalInfo)

	check(vk.QueueSubmit2(device.queues[.Graphics], 1, &submit, frame.renderFence))

	presentInfo := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.swapchain,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.renderSemaphore,
		pImageIndices      = &swapchainImageIndex,
	}

	res = vk.QueuePresentKHR(device.queues[.Graphics], &presentInfo)

	if res == .ERROR_OUT_OF_DATE_KHR {
		resizeRequested = true
		return
	}

	frameNumber += 1
}

DrawBackground :: proc(cmd: vk.CommandBuffer, using ctx: ^Context) {
	effect := computeEffects[currentEffect]

	vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)
	vk.CmdBindDescriptorSets(cmd, .COMPUTE, effect.layout, 0, 1, &drawImageDescriptors, 0, nil)

	vk.CmdPushConstants(
		cmd,
		effect.layout,
		{.COMPUTE},
		0,
		size_of(ComputePushConstants),
		&computeEffects[currentEffect].data,
	)

	vk.CmdDispatch(cmd, u32(drawExtent.width / 16.0) + 1, u32(drawExtent.height / 16.0) + 1, 1)
}

DrawGeometry :: proc(cmd: vk.CommandBuffer, using ctx: ^Context) {
	colorAttachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = drawImage.imageView,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	depthAttachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = depthImage.imageView,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {depthStencil = {depth = 0.0}},
	}

	renderArea := vk.Rect2D {
		extent = drawExtent,
	}

	renderInfo := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = renderArea,
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &colorAttachment,
		pDepthAttachment     = &depthAttachment,
	}

	vk.CmdBeginRendering(cmd, &renderInfo)

	vk.CmdBindPipeline(cmd, .GRAPHICS, meshPipeline)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(drawExtent.width),
		height   = f32(drawExtent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = drawExtent,
	}

	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	pushConstants: GpuPushConstants

	view := glm.mat4LookAt({0, 0, -5}, {0, 0, 0}, {0, 1, 0})
	proj := glm.mat4Perspective(
		glm.radians(f32(70)),
		f32(drawExtent.width) / f32(drawExtent.height),
		0.1,
		10000,
	)

	proj[1][1] *= -1

	mesh := testMeshes[2]

	pushConstants.vertexBuffer = mesh.meshBuffers.vertexBufferAddress
	pushConstants.worldMatrix = proj * view
	vk.CmdPushConstants(
		cmd,
		meshPipelineLayout,
		{.VERTEX},
		0,
		size_of(GpuPushConstants),
		&pushConstants,
	)
	vk.CmdBindIndexBuffer(cmd, mesh.meshBuffers.indexBuffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(cmd, mesh.surfaces[0].count, 1, mesh.surfaces[0].startIndex, 0, 0)

	vk.CmdEndRendering(cmd)
}

DrawImgui :: proc(using ctx: ^Context, cmd: vk.CommandBuffer, targetImageView: vk.ImageView) {
	colorAttachmentInfo := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = targetImageView,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	renderArea := vk.Rect2D {
		extent = swapchain.extent,
	}

	renderInfo := vk.RenderingInfo {
		sType                = .RENDERING_INFO,
		renderArea           = renderArea,
		layerCount           = 1,
		colorAttachmentCount = 1,
		pColorAttachments    = &colorAttachmentInfo,
	}

	vk.CmdBeginRendering(cmd, &renderInfo)

	imgui_impl_vulkan.RenderDrawData(im.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}

ImmediateSubmit :: proc(
	using ctx: ^ImmediateContext,
	fn: proc(_: ^ImmediateContext, _: vk.CommandBuffer),
) {
	check(vk.ResetFences(device.device, 1, &fence))
	check(vk.ResetCommandBuffer(commandBuffer, vk.CommandBufferResetFlags{}))

	cmd := commandBuffer

	cmdBeginInfo := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cmdBeginInfo))

	fn(ctx, cmd)

	check(vk.EndCommandBuffer(cmd))

	cmdInfo := CommandBufferSubmitInfo(cmd)
	submit := SubmitInfo(&cmdInfo, nil, nil)

	check(vk.QueueSubmit2(device.queues[.Graphics], 1, &submit, fence))
	check(vk.WaitForFences(device.device, 1, &fence, true, 9999999999))
}

UploadMesh :: proc(
	using ctx: ^ImmediateContext,
	indices: []u32,
	vertices: []Vertex,
) -> GpuMeshBuffers {
	vertexBufferSize := u64(len(vertices) * size_of(Vertex))
	indexBufferSize := u64(len(indices) * size_of(u32))

	newSurface: GpuMeshBuffers

	newSurface.vertexBuffer = CreateBuffer(
		device.allocator,
		vertexBufferSize,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)

	deviceAddressInfo := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = newSurface.vertexBuffer.buffer,
	}

	newSurface.vertexBufferAddress = vk.GetBufferDeviceAddress(device.device, &deviceAddressInfo)

	newSurface.indexBuffer = CreateBuffer(
		device.allocator,
		indexBufferSize,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.GPU_ONLY,
	)

	stagingBuffer := CreateBuffer(
		device.allocator,
		vertexBufferSize + indexBufferSize,
		{.TRANSFER_SRC},
		.CPU_ONLY,
	)

	data := stagingBuffer.allocationInfo.pMappedData

	mem.copy(data, raw_data(vertices), int(vertexBufferSize))
	mem.copy(
		mem.ptr_offset(cast(^byte)data, vertexBufferSize),
		raw_data(indices),
		int(indexBufferSize),
	)

	TempData :: struct {
		vertexBufferSize: u64,
		indexBufferSize:  u64,
		srcBuffer:        vk.Buffer,
		dstVertexBuffer:  vk.Buffer,
		dstIndexBuffer:   vk.Buffer,
	}

	tempData := TempData {
		vertexBufferSize = vertexBufferSize,
		indexBufferSize  = indexBufferSize,
		srcBuffer        = stagingBuffer.buffer,
		dstVertexBuffer  = newSurface.vertexBuffer.buffer,
		dstIndexBuffer   = newSurface.indexBuffer.buffer,
	}

	context.user_ptr = &tempData

	submitFn := proc(ctx: ^ImmediateContext, cmd: vk.CommandBuffer) {
		data := (cast(^TempData)context.user_ptr)^
		vertexCopy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = 0,
			size      = cast(vk.DeviceSize)data.vertexBufferSize,
		}
		vk.CmdCopyBuffer(cmd, data.srcBuffer, data.dstVertexBuffer, 1, &vertexCopy)

		indexCopy := vk.BufferCopy {
			dstOffset = 0,
			srcOffset = cast(vk.DeviceSize)data.vertexBufferSize,
			size      = cast(vk.DeviceSize)data.indexBufferSize,
		}
		vk.CmdCopyBuffer(cmd, data.srcBuffer, data.dstIndexBuffer, 1, &indexCopy)
	}

	ImmediateSubmit(ctx, submitFn)

	DestroyBuffer(device.allocator, stagingBuffer)

	return newSurface
}

InitDefaultData :: proc(using ctx: ^Context) {
}

DestroyDrawImage :: proc(using ctx: ^Context) {
	// DestroyFramebuffer
	DestroyImage(device, depthImage)
	DestroyImage(device, drawImage)
}

DestroyDrawImageDescriptors :: proc(using ctx: ^Context) {
	vk.DestroyDescriptorSetLayout(device.device, drawImageDescriptorLayout, nil)
}

ResizeDrawImage :: proc(using ctx: ^Context) {
	DestroyDrawImage(ctx)
	InitDrawImage(ctx)

	DestroyDrawImageDescriptors(ctx)
	InitDrawImageDescriptors(ctx)
}

InitDrawImage :: proc(using ctx: ^Context) {
	// TODO: Store the window extents
	drawImageExtent := vk.Extent3D{swapchain.extent.width, swapchain.extent.height, 1}

	drawImage.format = .R16G16B16A16_SFLOAT
	drawImage.extent = drawImageExtent

	drawImageUsage := vk.ImageUsageFlags{.TRANSFER_SRC, .TRANSFER_DST, .STORAGE, .COLOR_ATTACHMENT}

	drawImageInfo := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = drawImage.format,
		extent      = drawImage.extent,
		mipLevels   = 1,
		arrayLayers = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
		usage       = drawImageUsage,
	}

	drawImageAllocInfo := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	check(
		vma.CreateImage(
			device.allocator,
			&drawImageInfo,
			&drawImageAllocInfo,
			&drawImage.image,
			&drawImage.allocation,
			nil,
		),
	)

	drawImageViewInfo := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = drawImage.image,
		format = drawImage.format,
		subresourceRange = {
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = {.COLOR},
		},
	}

	check(vk.CreateImageView(device.device, &drawImageViewInfo, nil, &drawImage.imageView))

	depthImage.format = .D32_SFLOAT
	depthImage.extent = drawImageExtent

	depthImageUsage := vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}

	depthImageInfo := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		imageType   = .D2,
		format      = depthImage.format,
		extent      = depthImage.extent,
		mipLevels   = 1,
		arrayLayers = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
		usage       = depthImageUsage,
	}

	depthImageAllocInfo := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	check(
		vma.CreateImage(
			device.allocator,
			&depthImageInfo,
			&depthImageAllocInfo,
			&depthImage.image,
			&depthImage.allocation,
			nil,
		),
	)

	depthImageViewInfo := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = depthImage.image,
		format = depthImage.format,
		subresourceRange = {
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = {.DEPTH},
		},
	}

	check(vk.CreateImageView(device.device, &depthImageViewInfo, nil, &depthImage.imageView))
}

InitImmediateContext :: proc(using ctx: ^Context) {
	immedateContext.device = &device

	fenceInfo := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	check(vk.CreateFence(device.device, &fenceInfo, nil, &immedateContext.fence))

	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(device.queueIndices[.Graphics]),
	}

	check(vk.CreateCommandPool(device.device, &cmdPoolInfo, nil, &immedateContext.commandPool))

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = immedateContext.commandPool,
		commandBufferCount = 1,
		level              = .PRIMARY,
	}

	check(vk.AllocateCommandBuffers(device.device, &cmdAllocInfo, &immedateContext.commandBuffer))
}

DestroyImmediateContext :: proc(ctx: ImmediateContext) {
	vk.DestroyCommandPool(ctx.device.device, ctx.commandPool, nil)
	vk.DestroyFence(ctx.device.device, ctx.fence, nil)
}
