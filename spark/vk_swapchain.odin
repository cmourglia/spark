package spark

import "vendor:glfw"
import vk "vendor:vulkan"

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

InitSwapchain :: proc(device: Device, swapchain: ^Swapchain) {
	details := QuerySwapchainSupport(device)

	swapchain.format = ChooseSwapchainFormat(details.formats)
	swapchain.presentMode = ChooseSwapchainPresentMode(details.presentModes)
	swapchain.extent = ChooseSwapchainExtent(device.window, details.capabilities)

	imageCount := details.capabilities.minImageCount + 1
	if details.capabilities.maxImageCount > 0 {
		imageCount = max(imageCount, details.capabilities.maxImageCount)
	}

	info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = device.surface,
		minImageCount    = imageCount,
		imageFormat      = swapchain.format.format,
		imageColorSpace  = swapchain.format.colorSpace,
		imageExtent      = swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform     = details.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = swapchain.presentMode,
		clipped          = true,
		oldSwapchain     = vk.SwapchainKHR{},
	}

	queueFamilyIndices := [?]u32 {
		u32(device.queueIndices[.Graphics]),
		u32(device.queueIndices[.Present]),
	}
	if device.queueIndices[.Graphics] != device.queueIndices[.Present] {
		info.imageSharingMode = .CONCURRENT
		info.queueFamilyIndexCount = 2
		info.pQueueFamilyIndices = &queueFamilyIndices[0]
	}

	check(vk.CreateSwapchainKHR(device.device, &info, nil, &swapchain.swapchain))

	check(vk.GetSwapchainImagesKHR(device.device, swapchain.swapchain, &imageCount, nil))
	assert(imageCount > 0)
	swapchain.images = make([]vk.Image, imageCount)
	check(
		vk.GetSwapchainImagesKHR(
			device.device,
			swapchain.swapchain,
			&imageCount,
			&swapchain.images[0],
		),
	)

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

		check(vk.CreateImageView(device.device, &info, nil, &swapchain.imageViews[i]))
	}
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

QuerySwapchainSupport :: proc(device: Device) -> SwapchainSupportDetails {
	details: SwapchainSupportDetails

	formatCount: u32
	check(vk.GetPhysicalDeviceSurfaceFormatsKHR(device.gpu, device.surface, &formatCount, nil))
	assert(formatCount != 0)

	details.formats = make([]vk.SurfaceFormatKHR, formatCount, context.temp_allocator)
	check(
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device.gpu,
			device.surface,
			&formatCount,
			raw_data(details.formats),
		),
	)

	presentModeCount: u32
	check(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device.gpu,
			device.surface,
			&presentModeCount,
			nil,
		),
	)
	assert(presentModeCount != 0)

	details.presentModes = make([]vk.PresentModeKHR, presentModeCount, context.temp_allocator)
	check(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device.gpu,
			device.surface,
			&presentModeCount,
			raw_data(details.presentModes),
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

DestroySwapchain :: proc(device: Device, swapchain: ^Swapchain) {

	for view in swapchain.imageViews {
		vk.DestroyImageView(device.device, view, nil)
	}

	delete(swapchain.imageViews)
	delete(swapchain.images)

	vk.DestroySwapchainKHR(device.device, swapchain.swapchain, nil)
}

ResizeSwapchain :: proc(device: Device, swapchain: ^Swapchain) {
	vk.DeviceWaitIdle(device.device)

	DestroySwapchain(device, swapchain)

	InitSwapchain(device, swapchain)
}
