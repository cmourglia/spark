package spark

import "core:slice"
import vk "vendor:vulkan"

Descriptor_Pool_Size_Ratio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

Descriptor_Allocator :: struct {
	device:        vk.Device,
	ratios:        []Descriptor_Pool_Size_Ratio,
	full_pools:    [dynamic]vk.DescriptorPool,
	ready_pools:   [dynamic]vk.DescriptorPool,
	sets_per_pool: u32,
}

Descriptor_Writer :: struct {
	image_infos:  [8]vk.DescriptorImageInfo,
	buffer_infos: [8]vk.DescriptorBufferInfo,
	image_count:  int,
	buffer_count: int,
	writes:       [dynamic]vk.WriteDescriptorSet,
}

create_descriptor_allocator :: proc(
	device: Device,
	nbSets: u32,
	ratios: []Descriptor_Pool_Size_Ratio,
) -> Descriptor_Allocator {
	allocator: Descriptor_Allocator

	allocator.device = device.device
	allocator.ratios = slice.clone(ratios)
	allocator.sets_per_pool = grow_sets_per_pool(nbSets)
	append(&allocator.ready_pools, create_pool(device.device, nbSets, ratios))

	return allocator
}

@(private = "file")
grow_sets_per_pool :: proc(sets: u32) -> u32 {
	return min(4092, u32(f32(sets) * 1.5))
}

@(private = "file")
get_pool :: proc(using allocator: ^Descriptor_Allocator) -> vk.DescriptorPool {
	new_pool: vk.DescriptorPool

	if len(ready_pools) > 0 {
		new_pool = pop(&ready_pools)
	} else {
		new_pool = create_pool(device, sets_per_pool, ratios)
		sets_per_pool = grow_sets_per_pool(sets_per_pool)
	}

	return new_pool
}

@(private = "file")
create_pool :: proc(
	device: vk.Device,
	nbSets: u32,
	ratios: []Descriptor_Pool_Size_Ratio,
) -> vk.DescriptorPool {
	pool_sizes := make([]vk.DescriptorPoolSize, len(ratios), context.temp_allocator)
	for ratio, i in ratios {
		pool_sizes[i] = vk.DescriptorPoolSize {
			type            = ratio.type,
			descriptorCount = u32(ratio.ratio * f32(nbSets)),
		}
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = nbSets,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = &pool_sizes[0],
	}

	new_pool: vk.DescriptorPool

	vk.CreateDescriptorPool(device, &pool_info, nil, &new_pool)

	return new_pool
}

allocate_descriptor_set :: proc(
	using allocator: ^Descriptor_Allocator,
	layout: vk.DescriptorSetLayout,
	next: rawptr = nil,
) -> vk.DescriptorSet {
	pool := get_pool(allocator)

	layout := layout

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = next,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layout,
	}

	descriptor_set: vk.DescriptorSet

	result := vk.AllocateDescriptorSets(device, &alloc_info, &descriptor_set)

	for result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		append(&full_pools, pool)

		pool = get_pool(allocator)
		alloc_info.descriptorPool = pool

		result := vk.AllocateDescriptorSets(device, &alloc_info, &descriptor_set)
	}

	append(&ready_pools, pool)

	return descriptor_set
}

clear_descriptor_allocator_pools :: proc(using allocator: ^Descriptor_Allocator) {
	for pool in ready_pools {
		vk.ResetDescriptorPool(device, pool, {})
	}

	for pool in full_pools {
		vk.ResetDescriptorPool(device, pool, {})
		append(&ready_pools, pool)
	}

	clear(&full_pools)
}

destroy_descriptor_allocator :: proc(using allocator: Descriptor_Allocator) {
	for pool in ready_pools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}

	for pool in full_pools {
		vk.DestroyDescriptorPool(device, pool, nil)
	}

	delete(ratios)
	delete(full_pools)
	delete(ready_pools)
}

write_image_descriptor :: proc(
	using writer: ^Descriptor_Writer,
	binding: u32,
	image: Image,
	sampler: vk.Sampler,
	layout: vk.ImageLayout,
	descriptor_type: vk.DescriptorType,
) {
	assert(image_count < len(image_infos))

	image_info := vk.DescriptorImageInfo {
		sampler     = sampler,
		imageLayout = layout,
		imageView   = image.image_view,
	}

	image_index := image_count
	image_count += 1

	image_infos[image_index] = image_info

	image_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = {},
		descriptorCount = 1,
		descriptorType  = descriptor_type,
		pImageInfo      = &image_infos[image_index],
	}

	append(&writes, image_write)
}

write_buffer_descriptor :: proc(
	using writer: ^Descriptor_Writer,
	binding: u32,
	buffer: Buffer,
	size: u64,
	offset: u64,
	descriptor_type: vk.DescriptorType,
) {
	assert(buffer_count < len(buffer_infos))

	buffer_info := vk.DescriptorBufferInfo {
		buffer = buffer.buffer,
		offset = cast(vk.DeviceSize)offset,
		range  = cast(vk.DeviceSize)size,
	}

	buffer_index := buffer_count
	buffer_count += 1

	buffer_infos[buffer_index] = buffer_info

	buffer_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstBinding      = binding,
		dstSet          = {},
		descriptorCount = 1,
		descriptorType  = descriptor_type,
		pBufferInfo     = &buffer_infos[buffer_index],
	}

	append(&writes, buffer_write)
}

update_descriptor_set :: proc(
	using writer: ^Descriptor_Writer,
	device: Device,
	set: vk.DescriptorSet,
) {
	for &write in writes {
		write.dstSet = set
	}

	vk.UpdateDescriptorSets(device.device, u32(len(writes)), &writes[0], 0, nil)
}

clear_descriptor_writer :: proc(using writer: ^Descriptor_Writer) {
	delete(writes)
	image_count = 0
	buffer_count = 0
}

build_descriptor_layout :: proc(
	device: Device,
	bindings: []vk.DescriptorSetLayoutBinding,
	shader_stages: vk.ShaderStageFlags,
	next: rawptr,
	flags: vk.DescriptorSetLayoutCreateFlags,
) -> vk.DescriptorSetLayout {
	for &binding in bindings {
		// FIXME: This call might not work
		binding.stageFlags |= shader_stages
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

create_descriptor_pool :: proc(
	device: Device,
	max_sets: u32,
	pool_ratios: []Descriptor_Pool_Size_Ratio,
) -> vk.DescriptorPool {
	pool_sizes := make([dynamic]vk.DescriptorPoolSize, context.temp_allocator)
	for ratio in pool_ratios {
		append(
			&pool_sizes,
			vk.DescriptorPoolSize {
				type = ratio.type,
				descriptorCount = u32(ratio.ratio * f32(max_sets)),
			},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = max_sets,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = &pool_sizes[0],
	}

	pool: vk.DescriptorPool
	check(vk.CreateDescriptorPool(device.device, &pool_info, nil, &pool))

	return pool
}
