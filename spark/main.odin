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
	instance:                  vk.Instance,
	surface:                   vk.SurfaceKHR,
	gpu:                       vk.PhysicalDevice,
	device:                    vk.Device,
	queueIndices:              [QueueFamily]int,
	queues:                    [QueueFamily]vk.Queue,
	swapchain:                 Swapchain,
	swapchainSupport:          SwapchainSupportDetails,
	debugMessenger:            vk.DebugUtilsMessengerEXT,
	frames:                    [FRAME_OVERLAP]FrameData,
	allocator:                 vma.Allocator,
	drawImage:                 Image,
	depthImage:                Image,
	drawExtent:                vk.Extent2D,
	descriptorPool:            vk.DescriptorPool,
	drawImageDescriptors:      vk.DescriptorSet,
	drawImageDescriptorLayout: vk.DescriptorSetLayout,
	immFence:                  vk.Fence,
	immCommandBuffer:          vk.CommandBuffer,
	immCommandPool:            vk.CommandPool,
	imguiPool:                 vk.DescriptorPool,
	frameNumber:               int,
	gradientPipelineLayout:    vk.PipelineLayout,
	computeEffects:            [dynamic]ComputeEffect,
	currentEffect:             i32,
	meshPipelineLayout:        vk.PipelineLayout,
	meshPipeline:              vk.Pipeline,
	testMeshes:                []MeshAsset,
}

Swapchain :: struct {
	swapchain:   vk.SwapchainKHR,
	format:      vk.SurfaceFormatKHR,
	presentMode: vk.PresentModeKHR,
	extent:      vk.Extent2D,
	images:      []vk.Image,
	imageViews:  []vk.ImageView,
}

SwapchainSupportDetails :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
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
	CreateInstance(ctx)

	CreateSurface(ctx)
	PickPhysicalDevice(ctx)
	FindQueueFamilies(ctx)
	CreateDevice(ctx)

	for &q, i in queues {
		vk.GetDeviceQueue(device, u32(queueIndices[i]), 0, &q)
	}

	vulkan_functions := vma.create_vulkan_functions()
	allocator_info := vma.AllocatorCreateInfo {
		physicalDevice   = gpu,
		device           = device,
		instance         = instance,
		flags            = {.BUFFER_DEVICE_ADDRESS},
		pVulkanFunctions = &vulkan_functions,
	}
	check(vma.CreateAllocator(&allocator_info, &allocator))

	InitSwapchain(ctx)
	InitSwapchainViews(ctx)

	InitCommands(ctx)
	InitSyncStructures(ctx)
	InitDescriptors(ctx)
	InitPipelines(ctx)

	InitDefaultData(ctx)

	testMeshes = LoadGltf(ctx, "models/basicmesh.glb") or_else os.exit(1)

	InitImgui(ctx)

	free_all(context.temp_allocator)
}

DeinitVulkan :: proc(using ctx: ^Context) {
	vk.DeviceWaitIdle(device)

	// TODO: Deletion queue

	imgui_impl_vulkan.Shutdown()
	imgui_impl_glfw.Shutdown()
	vk.DestroyDescriptorPool(device, imguiPool, nil)
	im.DestroyContext()

	for mesh in testMeshes {
		DeleteMeshAsset(ctx, mesh)
	}
	delete(testMeshes)

	vk.DestroyCommandPool(device, immCommandPool, nil)
	vk.DestroyFence(device, immFence, nil)

	for effect in computeEffects {
		vk.DestroyPipeline(device, effect.pipeline, nil)
	}
	delete(computeEffects)

	vk.DestroyPipeline(device, meshPipeline, nil)
	vk.DestroyPipelineLayout(device, meshPipelineLayout, nil)
	vk.DestroyPipelineLayout(device, gradientPipelineLayout, nil)
	vk.DestroyDescriptorPool(device, descriptorPool, nil)
	vk.DestroyDescriptorSetLayout(device, drawImageDescriptorLayout, nil)

	for frame in frames {
		vk.DestroyFence(device, frame.renderFence, nil)
		vk.DestroySemaphore(device, frame.renderSemaphore, nil)
		vk.DestroySemaphore(device, frame.swapchainSemaphore, nil)
		vk.DestroyCommandPool(device, frame.commandPool, nil)
	}

	DestroySwapchain(ctx)

	vma.DestroyAllocator(allocator)

	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)

	when ODIN_DEBUG {
		vk.DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
	}

	vk.DestroyInstance(instance, nil)
}

DeinitWindow :: proc(using ctx: ^Context) {
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

MainLoop :: proc(using ctx: ^Context) {
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

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

CreateInstance :: proc(using ctx: ^Context) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))

	appInfo := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Spark",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "None",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &appInfo,
	}

	requiredExtensions := glfw.GetRequiredInstanceExtensions()
	extensions := make([dynamic]cstring, context.temp_allocator)

	for ext in requiredExtensions {
		append(&extensions, ext)
	}

	when ODIN_DEBUG {
		info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		debugMessenger_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE | .INFO | .WARNING | .ERROR},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = DebugCallback,
			pUserData       = transmute(rawptr)&g_ctx,
		}

		info.pNext = &debugMessenger_info
	}

	info.enabledExtensionCount = u32(len(extensions))
	info.ppEnabledExtensionNames = raw_data(extensions)

	check(vk.CreateInstance(&info, nil, &instance))

	vk.load_proc_addresses_instance(instance)

	when ODIN_DEBUG {
		check(
			vk.CreateDebugUtilsMessengerEXT(instance, &debugMessenger_info, nil, &debugMessenger),
		)
	}
}

CreateSurface :: proc(using ctx: ^Context) {
	check(glfw.CreateWindowSurface(instance, window, nil, &surface))
}

PickPhysicalDevice :: proc(using ctx: ^Context) {
	// TODO: Proper compat check
	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))

	assert(len(devices) > 0)

	ctx.gpu = devices[0]
}

FindQueueFamilies :: proc(using ctx: ^Context) {
	queueCount: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queueCount, nil)
	availableQueues := make([]vk.QueueFamilyProperties, queueCount, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queueCount, raw_data(availableQueues))

	for q, i in availableQueues {
		if .GRAPHICS in q.queueFlags && queueIndices[.Graphics] == -1 {
			queueIndices[.Graphics] = i
		}

		if .COMPUTE in q.queueFlags && queueIndices[.Compute] == -1 {
			queueIndices[.Compute] = i
		}

		presentSupport: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(gpu, u32(i), surface, &presentSupport)
		if presentSupport && queueIndices[.Present] == -1 {
			queueIndices[.Present] = i
		}

		allFound := true
		for qi in queueIndices {
			if qi == -1 {
				allFound = false
				break
			}
		}

		if allFound {
			break
		}
	}
}

CreateDevice :: proc(using ctx: ^Context) {
	uniqueIndices: map[int]b8
	defer delete(uniqueIndices)

	for i in queueIndices {
		uniqueIndices[i] = true
	}

	queueInfos := make([dynamic]vk.DeviceQueueCreateInfo, context.temp_allocator)
	for i in uniqueIndices {
		priority := f32(1)
		queue_info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = u32(i),
			queueCount       = 1,
			pQueuePriorities = &priority,
		}

		append(&queueInfos, queue_info)
	}

	deviceFeatures13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	deviceFeatures12 := vk.PhysicalDeviceVulkan12Features {
		sType               = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext               = &deviceFeatures13,
		bufferDeviceAddress = true,
		descriptorIndexing  = true,
	}

	deviceFeatures := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &deviceFeatures12,
	}

	deviceInfo := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &deviceFeatures,
		queueCreateInfoCount    = u32(len(queueInfos)),
		pQueueCreateInfos       = raw_data(queueInfos),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0],
	}

	check(vk.CreateDevice(gpu, &deviceInfo, nil, &device))
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

ChooseSwapchainExtent :: proc(
	window: glfw.WindowHandle,
	caps: vk.SurfaceCapabilitiesKHR,
) -> vk.Extent2D {
	if caps.currentExtent.width != max(u32) {
		return caps.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)
	actualExtent := vk.Extent2D{u32(width), u32(height)}

	actualExtent.width = clamp(
		actualExtent.width,
		caps.minImageExtent.width,
		caps.maxImageExtent.width,
	)
	actualExtent.height = clamp(
		actualExtent.height,
		caps.minImageExtent.height,
		caps.maxImageExtent.height,
	)

	return actualExtent
}

InitSwapchain :: proc(using ctx: ^Context) {
	QuerySwapchainSupport(ctx)

	swapchain.format = ChooseSwapchainFormat(swapchainSupport.formats)
	swapchain.presentMode = ChooseSwapchainPresentMode(swapchainSupport.presentModes)
	swapchain.extent = ChooseSwapchainExtent(window, swapchainSupport.capabilities)

	imageCount := swapchainSupport.capabilities.minImageCount + 1
	if swapchainSupport.capabilities.maxImageCount > 0 {
		imageCount = max(imageCount, swapchainSupport.capabilities.maxImageCount)
	}

	info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = imageCount,
		imageFormat      = swapchain.format.format,
		imageColorSpace  = swapchain.format.colorSpace,
		imageExtent      = swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform     = swapchainSupport.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = swapchain.presentMode,
		clipped          = true,
		oldSwapchain     = vk.SwapchainKHR{},
	}

	queueFamilyIndices := [?]u32{u32(queueIndices[.Graphics]), u32(queueIndices[.Present])}
	if queueIndices[.Graphics] != queueIndices[.Present] {
		info.imageSharingMode = .CONCURRENT
		info.queueFamilyIndexCount = 2
		info.pQueueFamilyIndices = &queueFamilyIndices[0]
	}

	check(vk.CreateSwapchainKHR(device, &info, nil, &swapchain.swapchain))

	check(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &imageCount, nil))
	assert(imageCount > 0)
	swapchain.images = make([]vk.Image, imageCount)
	check(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &imageCount, &swapchain.images[0]))

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
			allocator,
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

	check(vk.CreateImageView(device, &drawImageViewInfo, nil, &drawImage.imageView))

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
			allocator,
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

	check(vk.CreateImageView(device, &depthImageViewInfo, nil, &depthImage.imageView))
}

InitSwapchainViews :: proc(using ctx: ^Context) {
	swapchain.imageViews = make([]vk.ImageView, len(swapchain.images))

	for _, i in swapchain.imageViews {
		info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = swapchain.images[i],
			viewType = .D2,
			format = swapchain.format.format,
			components = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		check(vk.CreateImageView(device, &info, nil, &swapchain.imageViews[i]))
	}
}

QuerySwapchainSupport :: proc(using ctx: ^Context) {
	formatCount: u32
	check(vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &formatCount, nil))
	assert(formatCount != 0)

	swapchainSupport.formats = make([]vk.SurfaceFormatKHR, formatCount)
	check(
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			gpu,
			surface,
			&formatCount,
			raw_data(swapchainSupport.formats),
		),
	)

	presentModeCount: u32
	check(vk.GetPhysicalDeviceSurfacePresentModesKHR(gpu, surface, &presentModeCount, nil))
	assert(presentModeCount != 0)

	swapchainSupport.presentModes = make([]vk.PresentModeKHR, presentModeCount)
	check(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			gpu,
			surface,
			&presentModeCount,
			raw_data(swapchainSupport.presentModes),
		),
	)

	check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &swapchainSupport.capabilities))
}

InitCommands :: proc(using ctx: ^Context) {
	cmdPoolInfo := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = u32(queueIndices[.Graphics]),
	}

	for &frame in frames {
		check(vk.CreateCommandPool(device, &cmdPoolInfo, nil, &frame.commandPool))

		cmdAllocInfo := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = frame.commandPool,
			commandBufferCount = 1,
			level              = .PRIMARY,
		}

		check(vk.AllocateCommandBuffers(device, &cmdAllocInfo, &frame.commandBuffer))
	}

	check(vk.CreateCommandPool(device, &cmdPoolInfo, nil, &immCommandPool))

	cmdAllocInfo := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = immCommandPool,
		commandBufferCount = 1,
		level              = .PRIMARY,
	}

	check(vk.AllocateCommandBuffers(device, &cmdAllocInfo, &immCommandBuffer))
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
		check(vk.CreateFence(device, &fenceInfo, nil, &frame.renderFence))

		check(vk.CreateSemaphore(device, &semaphoreInfo, nil, &frame.swapchainSemaphore))
		check(vk.CreateSemaphore(device, &semaphoreInfo, nil, &frame.renderSemaphore))
	}

	check(vk.CreateFence(device, &fenceInfo, nil, &immFence))
}

InitDescriptors :: proc(using ctx: ^Context) {
	sizes := [?]DescriptorPoolSizeRatio{{.STORAGE_IMAGE, 1}}
	descriptorPool = CreateDescriptorPool(device, 10, sizes[:])

	bindings := [?]vk.DescriptorSetLayoutBinding {
		{binding = 0, descriptorType = .STORAGE_IMAGE, descriptorCount = 1},
	}

	drawImageDescriptorLayout = BuildDescriptorLayout(
		device,
		bindings[:],
		{.COMPUTE},
		nil,
		vk.DescriptorSetLayoutCreateFlags{},
	)

	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptorPool,
		descriptorSetCount = 1,
		pSetLayouts        = &drawImageDescriptorLayout,
	}

	check(vk.AllocateDescriptorSets(device, &allocInfo, &drawImageDescriptors))

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

	vk.UpdateDescriptorSets(device, 1, &drawImageWrite, 0, nil)
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
	check(vk.CreatePipelineLayout(device, &computeLayoutInfo, nil, &gradientPipelineLayout))

	gradientShader :=
		LoadShaderModule(device, "shaders/bin/gradient_color.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device, gradientShader, nil)

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
			device,
			vk.PipelineCache{},
			1,
			&gradientComputePipelineInfo,
			nil,
			&gradient.pipeline,
		),
	)

	append(&computeEffects, gradient)

	skyShader := LoadShaderModule(device, "shaders/bin/sky.comp.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device, skyShader, nil)

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
			device,
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
		LoadShaderModule(device, "shaders/bin/colored_triangle_mesh.vert.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device, triangleVertShader, nil)
	triangleFragShader :=
		LoadShaderModule(device, "shaders/bin/colored_triangle.frag.spv") or_else os.exit(1)
	defer vk.DestroyShaderModule(device, triangleFragShader, nil)

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
	check(vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &meshPipelineLayout))

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

	meshPipeline = BuildGraphicsPipeline(device, &pipelineConfig)
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

	check(vk.CreateDescriptorPool(device, &poolInfo, nil, &imguiPool))

	im.CreateContext()

	imgui_impl_glfw.InitForVulkan(window, true)

	initInfo := imgui_impl_vulkan.InitInfo {
		Instance              = instance,
		PhysicalDevice        = gpu,
		Device                = device,
		Queue                 = queues[.Graphics],
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
		&instance,
	)

	imgui_impl_vulkan.Init(&initInfo, 0)
	imgui_impl_vulkan.CreateFontsTexture()
}

Draw :: proc(using ctx: ^Context) {
	frame := frames[frameNumber % FRAME_OVERLAP]
	check(vk.WaitForFences(device, 1, &frame.renderFence, true, 1000000000))
	check(vk.ResetFences(device, 1, &frame.renderFence))

	swapchainImageIndex: u32
	check(
		vk.AcquireNextImageKHR(
			device,
			swapchain.swapchain,
			1000000000,
			frame.swapchainSemaphore,
			vk.Fence{},
			&swapchainImageIndex,
		),
	)

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

	check(vk.QueueSubmit2(queues[.Graphics], 1, &submit, frame.renderFence))

	presentInfo := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.swapchain,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &frame.renderSemaphore,
		pImageIndices      = &swapchainImageIndex,
	}

	check(vk.QueuePresentKHR(queues[.Graphics], &presentInfo))

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

	vk.CmdDispatch(cmd, u32(drawExtent.width / 16.0), u32(drawExtent.height / 16.0), 1)
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

	pushConstants : GpuPushConstants

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

DestroySwapchain :: proc(using ctx: ^Context) {
	vk.DestroyImageView(device, depthImage.imageView, nil)
	vma.DestroyImage(allocator, depthImage.image, depthImage.allocation)
	vk.DestroyImageView(device, drawImage.imageView, nil)
	vma.DestroyImage(allocator, drawImage.image, drawImage.allocation)

	for view in swapchain.imageViews {
		vk.DestroyImageView(device, view, nil)
	}

	delete(swapchain.imageViews)
	delete(swapchain.images)

	vk.DestroySwapchainKHR(device, swapchain.swapchain, nil)

	delete(swapchainSupport.formats)
	delete(swapchainSupport.presentModes)
}

ImmediateSubmit :: proc(using ctx: ^Context, fn: proc(ctx: ^Context, cmd: vk.CommandBuffer)) {
	check(vk.ResetFences(device, 1, &immFence))
	check(vk.ResetCommandBuffer(immCommandBuffer, vk.CommandBufferResetFlags{}))

	cmd := immCommandBuffer

	cmdBeginInfo := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	check(vk.BeginCommandBuffer(cmd, &cmdBeginInfo))

	fn(ctx, cmd)

	check(vk.EndCommandBuffer(cmd))

	cmdInfo := CommandBufferSubmitInfo(cmd)
	submit := SubmitInfo(&cmdInfo, nil, nil)

	check(vk.QueueSubmit2(queues[.Graphics], 1, &submit, immFence))
	check(vk.WaitForFences(device, 1, &immFence, true, 9999999999))
}

UploadMesh :: proc(using ctx: ^Context, indices: []u32, vertices: []Vertex) -> GpuMeshBuffers {
	vertexBufferSize := u64(len(vertices) * size_of(Vertex))
	indexBufferSize := u64(len(indices) * size_of(u32))

	newSurface: GpuMeshBuffers

	newSurface.vertexBuffer = CreateBuffer(
		allocator,
		vertexBufferSize,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.GPU_ONLY,
	)

	deviceAddressInfo := vk.BufferDeviceAddressInfo {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = newSurface.vertexBuffer.buffer,
	}

	newSurface.vertexBufferAddress = vk.GetBufferDeviceAddress(device, &deviceAddressInfo)

	newSurface.indexBuffer = CreateBuffer(
		allocator,
		indexBufferSize,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.GPU_ONLY,
	)

	stagingBuffer := CreateBuffer(
		allocator,
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

	submitFn := proc(ctx: ^Context, cmd: vk.CommandBuffer) {
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

	DestroyBuffer(allocator, stagingBuffer)

	return newSurface
}

InitDefaultData :: proc(using ctx: ^Context) {
}
