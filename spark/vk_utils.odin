package spark

import "base:runtime"
import "core:log"
import "core:math"
import "core:mem"
import vma "shared:odin-vma"
import vk "vendor:vulkan"

Image :: struct {
	image:      vk.Image,
	image_view: vk.ImageView,
	allocation: vma.Allocation,
	extent:     vk.Extent3D,
	format:     vk.Format,
}

Buffer :: struct {
	buffer:          vk.Buffer,
	allocation:      vma.Allocation,
	allocation_info: vma.AllocationInfo,
}

Queue_Family :: enum {
	Graphics,
	Compute,
	Present,
}

semaphore_submit_info :: proc(
	stage_mask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	info := vk.SemaphoreSubmitInfo {
		sType       = .SEMAPHORE_SUBMIT_INFO,
		semaphore   = semaphore,
		stageMask   = stage_mask,
		deviceIndex = 0,
		value       = 1,
	}

	return info
}

command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = cmd,
		deviceMask    = 0,
	}

	return info
}

submit_info :: proc(
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

transition_image :: proc(
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

blit_image :: proc(
	cmd: vk.CommandBuffer,
	src_image, dst_image: vk.Image,
	src_size, dst_size: vk.Extent2D,
) {
	blit_region := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		srcSubresource = {aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1, mipLevel = 0},
		dstSubresource = {aspectMask = {.COLOR}, baseArrayLayer = 0, layerCount = 1, mipLevel = 0},
	}

	blit_region.srcOffsets[1] = {i32(src_size.width), i32(src_size.height), 1}
	blit_region.dstOffsets[1] = {i32(dst_size.width), i32(dst_size.height), 1}

	blit_info := vk.BlitImageInfo2 {
		sType          = .BLIT_IMAGE_INFO_2,
		srcImage       = src_image,
		srcImageLayout = .TRANSFER_SRC_OPTIMAL,
		dstImage       = dst_image,
		dstImageLayout = .TRANSFER_DST_OPTIMAL,
		filter         = .LINEAR,
		regionCount    = 1,
		pRegions       = &blit_region,
	}

	vk.CmdBlitImage2(cmd, &blit_info)
}

create_buffer :: proc(
	device: Device,
	alloc_size: u64,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vk.MemoryPropertyFlags,
) -> Buffer {
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size  = cast(vk.DeviceSize)alloc_size,
		usage = usage,
	}

	alloc_info := vma.AllocationCreateInfo {
		usage         = memory_usage,
		requiredFlags = memory_flags,
		flags         = {.MAPPED},
	}

	buffer: Buffer
	check(
		vma.CreateBuffer(
			device.allocator,
			&buffer_info,
			&alloc_info,
			&buffer.buffer,
			&buffer.allocation,
			&buffer.allocation_info,
		),
	)

	return buffer
}

destroy_buffer :: proc(device: Device, buffer: Buffer) {
	vma.DestroyBuffer(device.allocator, buffer.buffer, buffer.allocation)
}

create_image :: proc(
	device: Device,
	size: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mipmapped: bool = false,
) -> Image {
	image := Image {
		format = format,
		extent = size,
	}

	image_info := vk.ImageCreateInfo {
		sType       = .IMAGE_CREATE_INFO,
		format      = format,
		usage       = usage,
		extent      = size,
		imageType   = .D2,
		arrayLayers = 1,
		mipLevels   = 1,
		samples     = {._1},
		tiling      = .OPTIMAL,
	}

	if mipmapped {
		nb_levels := math.log2(f32(max(size.width, size.height)))
		image_info.mipLevels = u32(math.floor(nb_levels)) + 1
	}

	alloc_info := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	check(
		vma.CreateImage(
			device.allocator,
			&image_info,
			&alloc_info,
			&image.image,
			&image.allocation,
			nil,
		),
	)

	image_view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = image.image,
		format = format,
		subresourceRange = {
			baseMipLevel = 0,
			levelCount = image_info.mipLevels,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = {.DEPTH if format == .D32_SFLOAT else .COLOR},
		},
	}

	check(vk.CreateImageView(device.device, &image_view_info, nil, &image.image_view))

	return image
}

create_image_with_data :: proc(
	ctx: ^Immediate_Context,
	data: rawptr,
	size: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mipmapped: bool = false,
) -> Image {
	data_size := size.depth * size.width * size.height * 4
	device := ctx.device^
	upload_buffer := create_buffer(
		device,
		u64(data_size),
		{.TRANSFER_SRC},
		.CPU_TO_GPU,
		{.DEVICE_LOCAL},
	)

	mem.copy(upload_buffer.allocation_info.pMappedData, data, int(data_size))

	image := create_image(device, size, format, usage | {.TRANSFER_DST | .TRANSFER_SRC}, mipmapped)

	Temp_Data :: struct {
		image:  vk.Image,
		size:   vk.Extent3D,
		buffer: vk.Buffer,
	}

	temp_data := Temp_Data {
		image  = image.image,
		size   = size,
		buffer = upload_buffer.buffer,
	}

	context.user_ptr = &temp_data

	submit_fn := proc(ctx: ^Immediate_Context, cmd: vk.CommandBuffer) {
		data := (cast(^Temp_Data)context.user_ptr)^

		transition_image(cmd, data.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copy_region := vk.BufferImageCopy {
			bufferOffset = 0,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageExtent = data.size,
			imageSubresource = {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		vk.CmdCopyBufferToImage(
			cmd,
			data.buffer,
			data.image,
			.TRANSFER_DST_OPTIMAL,
			1,
			&copy_region,
		)

		transition_image(cmd, data.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	immediate_submit(ctx, submit_fn)

	destroy_buffer(device, upload_buffer)

	return image
}

destroy_image :: proc(device: Device, image: Image) {
	vk.DestroyImageView(device.device, image.image_view, nil)
	vma.DestroyImage(device.allocator, image.image, image.allocation)
}

debug_callback :: proc "system" (
	msg_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = (cast(^runtime.Context)user_data)^

	level: log.Level
	if .ERROR in msg_severity {
		level = .Error
	} else if .WARNING in msg_severity {
		level = .Warning
	} else if .INFO in msg_severity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "vulkan[%v]: %s", msg_type, callback_data.pMessage)

	return false
}

check :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure %v", result, location = loc)
	}
}
