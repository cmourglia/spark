package spark

import "vendor:glfw"
import vk "vendor:vulkan"

Swapchain :: struct {
	swapchain:    vk.SwapchainKHR,
	format:       vk.SurfaceFormatKHR,
	present_mode: vk.PresentModeKHR,
	extent:       vk.Extent2D,
	images:       []vk.Image,
	image_views:  []vk.ImageView,
}

Swapchain_Support_Details :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

init_swapchain :: proc(device: Device, swapchain: ^Swapchain) {
	details := query_swapchain_support(device)

	swapchain.format = choose_swapchain_format(details.formats)
	swapchain.present_mode = choose_swapchain_present_mode(details.present_modes)
	swapchain.extent = choose_swapchain_extent(device.window, details.capabilities)

	image_count := details.capabilities.minImageCount + 1
	if details.capabilities.maxImageCount > 0 {
		image_count = max(image_count, details.capabilities.maxImageCount)
	}

	info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = device.surface,
		minImageCount    = image_count,
		imageFormat      = swapchain.format.format,
		imageColorSpace  = swapchain.format.colorSpace,
		imageExtent      = swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform     = details.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = swapchain.present_mode,
		clipped          = true,
		oldSwapchain     = vk.SwapchainKHR{},
	}

	queue_family_indices := [?]u32 {
		u32(device.queue_indices[.Graphics]),
		u32(device.queue_indices[.Present]),
	}
	if device.queue_indices[.Graphics] != device.queue_indices[.Present] {
		info.imageSharingMode = .CONCURRENT
		info.queueFamilyIndexCount = 2
		info.pQueueFamilyIndices = &queue_family_indices[0]
	}

	check(vk.CreateSwapchainKHR(device.device, &info, nil, &swapchain.swapchain))

	check(vk.GetSwapchainImagesKHR(device.device, swapchain.swapchain, &image_count, nil))
	assert(image_count > 0)
	swapchain.images = make([]vk.Image, image_count)
	check(
		vk.GetSwapchainImagesKHR(
			device.device,
			swapchain.swapchain,
			&image_count,
			&swapchain.images[0],
		),
	)

	swapchain.image_views = make([]vk.ImageView, len(swapchain.images))

	for _, i in swapchain.image_views {
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

		check(vk.CreateImageView(device.device, &info, nil, &swapchain.image_views[i]))
	}
}

@(private = "file")
choose_swapchain_extent :: proc(
	window: glfw.WindowHandle,
	caps: vk.SurfaceCapabilitiesKHR,
) -> vk.Extent2D {
	if caps.currentExtent.width != max(u32) {
		return caps.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)
	actual_extent := vk.Extent2D{u32(width), u32(height)}

	actual_extent.width = clamp(
		actual_extent.width,
		caps.minImageExtent.width,
		caps.maxImageExtent.width,
	)
	actual_extent.height = clamp(
		actual_extent.height,
		caps.minImageExtent.height,
		caps.maxImageExtent.height,
	)

	return actual_extent
}

@(private = "file")
query_swapchain_support :: proc(device: Device) -> Swapchain_Support_Details {
	details: Swapchain_Support_Details

	format_count: u32
	check(vk.GetPhysicalDeviceSurfaceFormatsKHR(device.gpu, device.surface, &format_count, nil))
	assert(format_count != 0)

	details.formats = make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
	check(
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device.gpu,
			device.surface,
			&format_count,
			raw_data(details.formats),
		),
	)

	present_mode_count: u32
	check(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device.gpu,
			device.surface,
			&present_mode_count,
			nil,
		),
	)
	assert(present_mode_count != 0)

	details.present_modes = make([]vk.PresentModeKHR, present_mode_count, context.temp_allocator)
	check(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device.gpu,
			device.surface,
			&present_mode_count,
			raw_data(details.present_modes),
		),
	)

	check(
		vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
			device.gpu,
			device.surface,
			&details.capabilities,
		),
	)

	return details
}

@(private = "file")
choose_swapchain_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SNORM && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	return formats[0]
}

@(private = "file")
choose_swapchain_present_mode :: proc(presentModes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// TODO: Change this at some point
	//for mode in presentModes {
	//	if mode == .MAILBOX {
	//		return mode
	//	}
	//}

	return .FIFO
}


destroy_swapchain :: proc(device: Device, swapchain: ^Swapchain) {

	for view in swapchain.image_views {
		vk.DestroyImageView(device.device, view, nil)
	}

	delete(swapchain.image_views)
	delete(swapchain.images)

	vk.DestroySwapchainKHR(device.device, swapchain.swapchain, nil)
}

resize_swapchain :: proc(device: Device, swapchain: ^Swapchain) {
	vk.DeviceWaitIdle(device.device)

	destroy_swapchain(device, swapchain)

	init_swapchain(device, swapchain)
}
