package spark

import vma "shared:odin-vma"
import "vendor:glfw"
import vk "vendor:vulkan"

Device :: struct {
	window:         glfw.WindowHandle,
	instance:       vk.Instance,
	surface:        vk.SurfaceKHR,
	gpu:            vk.PhysicalDevice,
	device:         vk.Device,
	queueIndices:   [QueueFamily]int,
	queues:         [QueueFamily]vk.Queue,
	allocator:      vma.Allocator,
	debugMessenger: vk.DebugUtilsMessengerEXT,
}

InitDevice :: proc(window: glfw.WindowHandle) -> Device {
	device: Device
	device.window = window

	CreateInstance(&device)
	CreateSurface(&device)
	PickPhysicalDevice(&device)
	FindQueueFamilies(&device)
	CreateDevice(&device)

	for &q, i in device.queues {
		vk.GetDeviceQueue(device.device, u32(device.queueIndices[i]), 0, &q)
	}

	vulkan_functions := vma.create_vulkan_functions()
	allocator_info := vma.AllocatorCreateInfo {
		physicalDevice   = device.gpu,
		device           = device.device,
		instance         = device.instance,
		flags            = {.BUFFER_DEVICE_ADDRESS},
		pVulkanFunctions = &vulkan_functions,
	}
	check(vma.CreateAllocator(&allocator_info, &device.allocator))

	return device
}

@(private = "file")
CreateInstance :: proc(device: ^Device) {
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

	check(vk.CreateInstance(&info, nil, &device.instance))

	vk.load_proc_addresses_instance(device.instance)

	when ODIN_DEBUG {
		check(
			vk.CreateDebugUtilsMessengerEXT(
				device.instance,
				&debugMessenger_info,
				nil,
				&device.debugMessenger,
			),
		)
	}
}

CreateSurface :: proc(device: ^Device) {
	check(glfw.CreateWindowSurface(device.instance, device.window, nil, &device.surface))
}

PickPhysicalDevice :: proc(device: ^Device) {
	// TODO: Proper compat check
	device_count: u32
	vk.EnumeratePhysicalDevices(device.instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(device.instance, &device_count, raw_data(devices))

	assert(len(devices) > 0)

	device.gpu = devices[0]
}

FindQueueFamilies :: proc(device: ^Device) {
	queueCount: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device.gpu, &queueCount, nil)
	availableQueues := make([]vk.QueueFamilyProperties, queueCount, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device.gpu, &queueCount, raw_data(availableQueues))

	for q, i in availableQueues {
		if .GRAPHICS in q.queueFlags && device.queueIndices[.Graphics] == -1 {
			device.queueIndices[.Graphics] = i
		}

		if .COMPUTE in q.queueFlags && device.queueIndices[.Compute] == -1 {
			device.queueIndices[.Compute] = i
		}

		presentSupport: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device.gpu, u32(i), device.surface, &presentSupport)
		if presentSupport && device.queueIndices[.Present] == -1 {
			device.queueIndices[.Present] = i
		}

		allFound := true
		for qi in device.queueIndices {
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

CreateDevice :: proc(device: ^Device) {
	uniqueIndices: map[int]b8
	defer delete(uniqueIndices)

	for i in device.queueIndices {
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

	check(vk.CreateDevice(device.gpu, &deviceInfo, nil, &device.device))
}

DeinitDevice :: proc(device: ^Device) {
	vma.DestroyAllocator(device.allocator)

	vk.DestroyDevice(device.device, nil)
	vk.DestroySurfaceKHR(device.instance, device.surface, nil)

	when ODIN_DEBUG {
		vk.DestroyDebugUtilsMessengerEXT(device.instance, device.debugMessenger, nil)
	}

	vk.DestroyInstance(device.instance, nil)
}
