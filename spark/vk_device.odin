package spark

import vma "shared:odin-vma"
import "vendor:glfw"
import vk "vendor:vulkan"

Device :: struct {
	window:          glfw.WindowHandle,
	instance:        vk.Instance,
	surface:         vk.SurfaceKHR,
	gpu:             vk.PhysicalDevice,
	device:          vk.Device,
	queue_indices:   [Queue_Family]int,
	queues:          [Queue_Family]vk.Queue,
	allocator:       vma.Allocator,
	debug_messenger: vk.DebugUtilsMessengerEXT,
}

init_device :: proc(window: glfw.WindowHandle) -> Device {
	device: Device
	device.window = window

	create_instance(&device)
	create_surface(&device)
	pick_physical_device(&device)
	find_queue_families(&device)
	create_device(&device)

	for &q, i in device.queues {
		vk.GetDeviceQueue(device.device, u32(device.queue_indices[i]), 0, &q)
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
create_instance :: proc(device: ^Device) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Spark",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "None",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
	}

	required_extensions := glfw.GetRequiredInstanceExtensions()
	extensions := make([dynamic]cstring, context.temp_allocator)

	for ext in required_extensions {
		append(&extensions, ext)
	}

	when ODIN_DEBUG {
		info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		debug_messenger_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE | .INFO | .WARNING | .ERROR},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = debug_callback,
			pUserData       = transmute(rawptr)&g_ctx,
		}

		info.pNext = &debug_messenger_info
	}

	info.enabledExtensionCount = u32(len(extensions))
	info.ppEnabledExtensionNames = raw_data(extensions)

	check(vk.CreateInstance(&info, nil, &device.instance))

	vk.load_proc_addresses_instance(device.instance)

	when ODIN_DEBUG {
		check(
			vk.CreateDebugUtilsMessengerEXT(
				device.instance,
				&debug_messenger_info,
				nil,
				&device.debug_messenger,
			),
		)
	}
}

@(private = "file")
create_surface :: proc(device: ^Device) {
	check(glfw.CreateWindowSurface(device.instance, device.window, nil, &device.surface))
}

@(private = "file")
pick_physical_device :: proc(device: ^Device) {
	// TODO: Proper compat check
	device_count: u32
	vk.EnumeratePhysicalDevices(device.instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(device.instance, &device_count, raw_data(devices))

	assert(len(devices) > 0)

	device.gpu = devices[0]
}

@(private = "file")
find_queue_families :: proc(device: ^Device) {
	queue_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device.gpu, &queue_count, nil)
	available_queues := make([]vk.QueueFamilyProperties, queue_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device.gpu, &queue_count, raw_data(available_queues))

	for q, i in available_queues {
		if .GRAPHICS in q.queueFlags && device.queue_indices[.Graphics] == -1 {
			device.queue_indices[.Graphics] = i
		}

		if .COMPUTE in q.queueFlags && device.queue_indices[.Compute] == -1 {
			device.queue_indices[.Compute] = i
		}

		present_support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device.gpu, u32(i), device.surface, &present_support)
		if present_support && device.queue_indices[.Present] == -1 {
			device.queue_indices[.Present] = i
		}

		all_found := true
		for qi in device.queue_indices {
			if qi == -1 {
				all_found = false
				break
			}
		}

		if all_found {
			break
		}
	}
}

@(private = "file")
create_device :: proc(device: ^Device) {
	unique_indices: map[int]b8
	defer delete(unique_indices)

	for i in device.queue_indices {
		unique_indices[i] = true
	}

	queue_infos := make([dynamic]vk.DeviceQueueCreateInfo, context.temp_allocator)
	for i in unique_indices {
		priority := f32(1)
		queue_info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = u32(i),
			queueCount       = 1,
			pQueuePriorities = &priority,
		}

		append(&queue_infos, queue_info)
	}

	device_features_13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	device_features_12 := vk.PhysicalDeviceVulkan12Features {
		sType               = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext               = &device_features_13,
		bufferDeviceAddress = true,
		descriptorIndexing  = true,
	}

	device_features := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &device_features_12,
	}

	device_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &device_features,
		queueCreateInfoCount    = u32(len(queue_infos)),
		pQueueCreateInfos       = raw_data(queue_infos),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0],
	}

	check(vk.CreateDevice(device.gpu, &device_info, nil, &device.device))
}

deinit_device :: proc(device: ^Device) {
	vma.DestroyAllocator(device.allocator)

	vk.DestroyDevice(device.device, nil)
	vk.DestroySurfaceKHR(device.instance, device.surface, nil)

	when ODIN_DEBUG {
		vk.DestroyDebugUtilsMessengerEXT(device.instance, device.debug_messenger, nil)
	}

	vk.DestroyInstance(device.instance, nil)
}
