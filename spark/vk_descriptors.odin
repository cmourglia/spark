package spark

import "core:slice"
import vk "vendor:vulkan"

DescriptorPoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

DescriptorAllocator :: struct {
	device:      vk.Device,
	ratios:      []DescriptorPoolSizeRatio,
	fullPools:   [dynamic]vk.DescriptorPool,
	readyPools:  [dynamic]vk.DescriptorPool,
	setsPerPool: u32,
}

DescriptorWriter :: struct {
	imageInfos:  [8]vk.DescriptorImageInfo,
	bufferInfos: [8]vk.DescriptorBufferInfo,
	imageCount:  int,
	bufferCount: int,
	writes:      [dynamic]vk.WriteDescriptorSet,
}

CreateDescriptorAllocator :: proc(
	device: Device,
	nbSets: u32,
	ratios: []DescriptorPoolSizeRatio,
) -> DescriptorAllocator {
	allocator: DescriptorAllocator

	allocator.device = device.device
	allocator.ratios = slice.clone(ratios)
	allocator.setsPerPool = GrowSetsPerPool(nbSets)
	append(&allocator.readyPools, CreatePool(device.device, nbSets, ratios))

	return allocator
}

@(private = "file")
GrowSetsPerPool :: proc(sets: u32) -> u32 {
	return min(4092, u32(f32(sets) * 1.5))
}

@(private = "file")
GetPool :: proc(using allocator: ^DescriptorAllocator) -> vk.DescriptorPool {
	newPool: vk.DescriptorPool

	if len(readyPools) > 0 {
		newPool = pop(&readyPools)
	} else {
		newPool = CreatePool(device, setsPerPool, ratios)
		setsPerPool = GrowSetsPerPool(setsPerPool)
	}

	return newPool
}

@(private = "file")
CreatePool :: proc(
	device: vk.Device,
	nbSets: u32,
	ratios: []DescriptorPoolSizeRatio,
) -> vk.DescriptorPool {
	poolSizes := make([]vk.DescriptorPoolSize, len(ratios), context.temp_allocator)
	for ratio, i in ratios {
		poolSizes[i] = vk.DescriptorPoolSize {
			type            = ratio.type,
			descriptorCount = u32(ratio.ratio * f32(nbSets)),
		}
	}

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = nbSets,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = &poolSizes[0],
	}

	newPool: vk.DescriptorPool

	vk.CreateDescriptorPool(device, &poolInfo, nil, &newPool)

	return newPool
}

AllocateDescriptorSet :: proc(
	using allocator: ^DescriptorAllocator,
	layout: vk.DescriptorSetLayout,
	pNext: rawptr = nil,
) -> vk.DescriptorSet {
	pool := GetPool(allocator)

	layout := layout

	allocInfo := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = pNext,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layout,
	}

	descriptorSet: vk.DescriptorSet

	result := vk.AllocateDescriptorSets(device, &allocInfo, &descriptorSet)

	for result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		append(&fullPools, pool)

		pool = GetPool(allocator)
		allocInfo.descriptorPool = pool

		result := vk.AllocateDescriptorSets(device, &allocInfo, &descriptorSet)
	}

    append(&readyPools, pool)

	return descriptorSet
}

ClearDescriptorAllocatorPools :: proc(using allocator: ^DescriptorAllocator) {
	for pool in readyPools {
		vk.ResetDescriptorPool(device, pool, {})
	}

	for pool in fullPools {
		vk.ResetDescriptorPool(device, pool, {})
		append(&readyPools, pool)
	}

	clear(&fullPools)
}

DestroyDescriptorAllocator :: proc(using allocator: DescriptorAllocator) {
	for pool in readyPools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}

	for pool in fullPools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}

	delete(ratios)
	delete(fullPools)
	delete(readyPools)
}

WriteImageDescriptor :: proc(
	using writer: ^DescriptorWriter,
	binding: u32,
	image: Image,
	sampler: vk.Sampler,
	layout: vk.ImageLayout,
	descriptorType: vk.DescriptorType,
) {
	assert(imageCount < len(imageInfos))

	imageInfo := vk.DescriptorImageInfo {
		imageLayout = layout,
		imageView   = image.imageView,
	}

	imageIndex := imageCount
	imageCount += 1

	imageInfos[imageIndex] = imageInfo

	imageWrite := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = {},
		descriptorCount = 1,
		descriptorType  = descriptorType,
		pImageInfo      = &imageInfos[imageIndex],
	}

	append(&writes, imageWrite)
}

WriteBufferDescriptor :: proc(
	using writer: ^DescriptorWriter,
	binding: u32,
	buffer: Buffer,
	size: u64,
	offset: u64,
	descriptorType: vk.DescriptorType,
) {
	assert(bufferCount < len(bufferInfos))

	bufferInfo := vk.DescriptorBufferInfo {
		buffer = buffer.buffer,
		offset = cast(vk.DeviceSize)offset,
		range  = cast(vk.DeviceSize)size,
	}

	bufferIndex := bufferCount
	bufferCount += 1

	bufferInfos[bufferIndex] = bufferInfo

	bufferWrite := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = {},
		descriptorCount = 1,
		descriptorType  = descriptorType,
		pBufferInfo     = &bufferInfos[bufferIndex],
	}

	append(&writes, bufferWrite)
}

UpdateDescriptorSet :: proc(
	using writer: ^DescriptorWriter,
	device: Device,
	set: vk.DescriptorSet,
) {
	for &write in writes {
		write.dstSet = set
	}

	vk.UpdateDescriptorSets(device.device, u32(len(writes)), &writes[0], 0, nil)
}

ClearDescriptorWriter :: proc(using writer: ^DescriptorWriter) {
	delete(writes)
	imageCount = 0
	bufferCount = 0
}

BuildDescriptorLayout :: proc(
	device: Device,
	bindings: []vk.DescriptorSetLayoutBinding,
	shaderStages: vk.ShaderStageFlags,
	pNext: rawptr,
	flags: vk.DescriptorSetLayoutCreateFlags,
) -> vk.DescriptorSetLayout {
	for &binding in bindings {
		// FIXME: This call might not work
		binding.stageFlags |= shaderStages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		flags        = flags,
		bindingCount = u32(len(bindings)),
		pBindings    = &bindings[0],
	}

	set: vk.DescriptorSetLayout
	check(vk.CreateDescriptorSetLayout(device.device, &info, nil, &set))

	return set
}

CreateDescriptorPool :: proc(
	device: Device,
	maxSets: u32,
	poolRatios: []DescriptorPoolSizeRatio,
) -> vk.DescriptorPool {
	poolSizes := make([dynamic]vk.DescriptorPoolSize, context.temp_allocator)
	for ratio in poolRatios {
		append(
			&poolSizes,
			vk.DescriptorPoolSize {
				type = ratio.type,
				descriptorCount = u32(ratio.ratio * f32(maxSets)),
			},
		)
	}

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = maxSets,
		poolSizeCount = u32(len(poolSizes)),
		pPoolSizes    = &poolSizes[0],
	}

	pool: vk.DescriptorPool
	check(vk.CreateDescriptorPool(device.device, &poolInfo, nil, &pool))

	return pool
}
