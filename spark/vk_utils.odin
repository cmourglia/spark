package spark

import "base:runtime"
import "core:log"
import vma "shared:odin-vma"
import vk "vendor:vulkan"

Image :: struct {
	image:      vk.Image,
	imageView:  vk.ImageView,
	allocation: vma.Allocation,
	extent:     vk.Extent3D,
	format:     vk.Format,
}

Buffer :: struct {
	buffer:         vk.Buffer,
	allocation:     vma.Allocation,
	allocationInfo: vma.AllocationInfo,
}

QueueFamily :: enum {
	Graphics,
	Compute,
	Present,
}


SemaphoreSubmitInfo :: proc(
	stageMask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	info := vk.SemaphoreSubmitInfo {
		sType       = .SEMAPHORE_SUBMIT_INFO,
		semaphore   = semaphore,
		stageMask   = stageMask,
		deviceIndex = 0,
		value       = 1,
	}

	return info
}

CommandBufferSubmitInfo :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = cmd,
		deviceMask    = 0,
	}

	return info
}

SubmitInfo :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	wait_semaphore: ^vk.SemaphoreSubmitInfo,
	signal_semaphore: ^vk.SemaphoreSubmitInfo,
) -> vk.SubmitInfo2 {
	info := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = 1 if wait_semaphore != nil else 0,
		pWaitSemaphoreInfos      = wait_semaphore,
		signalSemaphoreInfoCount = 1 if signal_semaphore != nil else 0,
		pSignalSemaphoreInfos    = signal_semaphore,
		commandBufferInfoCount   = 1 if cmd != nil else 0,
		pCommandBufferInfos      = cmd,
	}

	return info
}

TransitionImage :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
) {
	aspect_mask: vk.ImageAspectFlags =
		{.DEPTH} if new_layout == .DEPTH_ATTACHMENT_OPTIMAL else {.COLOR}

	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = {.ALL_COMMANDS},
		srcAccessMask = {.MEMORY_WRITE},
		dstStageMask = {.ALL_COMMANDS},
		dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ},
		oldLayout = old_layout,
		newLayout = new_layout,
		image = image,
		subresourceRange = {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = vk.REMAINING_MIP_LEVELS,
			baseArrayLayer = 0,
			layerCount = vk.REMAINING_ARRAY_LAYERS,
		},
	}

	dep_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

BlitImage :: proc(
	cmd: vk.CommandBuffer,
	srcImage, dstImage: vk.Image,
	srcSize, dstSize: vk.Extent2D,
) {
	blitRegion := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		srcSubresource = {aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1, mipLevel = 0},
		dstSubresource = {aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1, mipLevel = 0},
	}

	blitRegion.srcOffsets[1] = {i32(srcSize.width), i32(srcSize.height), 1}
	blitRegion.dstOffsets[1] = {i32(dstSize.width), i32(dstSize.height), 1}

	blitInfo := vk.BlitImageInfo2 {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = srcImage,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		dstImage       = dstImage,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = &blitRegion,
	}

	vk.CmdBlitImage2(cmd, &blitInfo)
}

BuildDescriptorLayout :: proc(
	device: vk.Device,
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
	check(vk.CreateDescriptorSetLayout(device, &info, nil, &set))

	return set
}

DescriptorPoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

CreateDescriptorPool :: proc(
	device: vk.Device,
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
	check(vk.CreateDescriptorPool(device, &poolInfo, nil, &pool))

	return pool
}

CreateBuffer :: proc(
	allocator: vma.Allocator,
	allocSize: u64,
	usage: vk.BufferUsageFlags,
	memoryUsage: vma.MemoryUsage,
) -> Buffer {
	bufferInfo := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = cast(vk.DeviceSize)allocSize,
		usage = usage,
	}

	allocInfo := vma.AllocationCreateInfo {
		usage = memoryUsage,
		flags = {.MAPPED},
	}

	buffer: Buffer

	check(
		vma.CreateBuffer(
			allocator,
			&bufferInfo,
			&allocInfo,
			&buffer.buffer,
			&buffer.allocation,
			&buffer.allocationInfo,
		),
	)

	return buffer
}

DestroyBuffer :: proc(allocator: vma.Allocator, buffer: Buffer)
{
    vma.DestroyBuffer(allocator, buffer.buffer, buffer.allocation)
}

DebugCallback :: proc "system" (
	msgSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	msgType: vk.DebugUtilsMessageTypeFlagsEXT,
	callbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	userData: rawptr,
) -> b32 {
	context = (cast(^runtime.Context)userData)^

	level: log.Level
	if .ERROR in msgSeverity {
		level = .Error
	} else if .WARNING in msgSeverity {
		level = .Warning
	} else if .INFO in msgSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "vulkan[%v]: %s", msgType, callbackData.pMessage)

	return false
}

check :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure %v", result, location = loc)
	}
}
