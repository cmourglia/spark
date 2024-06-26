package spark

import "base:runtime"
import "core:log"
import "core:math"
import "core:mem"
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

CreateBuffer :: proc(
	device: Device,
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
			device.allocator,
			&bufferInfo,
			&allocInfo,
			&buffer.buffer,
			&buffer.allocation,
			&buffer.allocationInfo,
		),
	)

	return buffer
}

DestroyBuffer :: proc(device: Device, buffer: Buffer) {
	vma.DestroyBuffer(device.allocator, buffer.buffer, buffer.allocation)
}

CreateImage :: proc(
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

	imageInfo := vk.ImageCreateInfo {
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
		nbLevels := math.log2(f32(max(size.width, size.height)))
		imageInfo.mipLevels = u32(math.floor(nbLevels)) + 1
	}

	allocInfo := vma.AllocationCreateInfo {
		usage         = .GPU_ONLY,
		requiredFlags = {.DEVICE_LOCAL},
	}

	check(
		vma.CreateImage(
			device.allocator,
			&imageInfo,
			&allocInfo,
			&image.image,
			&image.allocation,
			nil,
		),
	)

	imageViewInfo := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		viewType = .D2,
		image = image.image,
		format = format,
		subresourceRange = {
			baseMipLevel = 0,
			levelCount = imageInfo.mipLevels,
			baseArrayLayer = 0,
			layerCount = 1,
			aspectMask = {.DEPTH if format == .D32_SFLOAT else .COLOR},
		},
	}

	check(vk.CreateImageView(device.device, &imageViewInfo, nil, &image.imageView))

	return image
}

CreateImageWithData :: proc(
	ctx: ^ImmediateContext,
	data: rawptr,
	size: vk.Extent3D,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	mipmapped: bool = false,
) -> Image {
	dataSize := size.depth * size.width * size.height * 4
	device := ctx.device^
	uploadBuffer := CreateBuffer(device, u64(dataSize), {.TRANSFER_SRC}, .CPU_TO_GPU)

	mem.copy(uploadBuffer.allocationInfo.pMappedData, data, int(dataSize))

	image := CreateImage(
		device,
		size,
		format,
		usage | {.TRANSFER_DST | .TRANSFER_SRC},
		mipmapped,
	)

	TempData :: struct {
		image:  vk.Image,
		size:   vk.Extent3D,
		buffer: vk.Buffer,
	}

	tempData := TempData {
		image  = image.image,
		size   = size,
		buffer = uploadBuffer.buffer,
	}

	context.user_ptr = &tempData

	submitFn := proc(ctx: ^ImmediateContext, cmd: vk.CommandBuffer) {
		data := (cast(^TempData)context.user_ptr)^

		TransitionImage(cmd, data.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

		copyRegion := vk.BufferImageCopy {
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
			&copyRegion,
		)

        TransitionImage(cmd, data.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	ImmediateSubmit(ctx, submitFn)

    DestroyBuffer(device, uploadBuffer)

	return image
}

DestroyImage :: proc(device: Device, image: Image) {
	vk.DestroyImageView(device.device, image.imageView, nil)
	vma.DestroyImage(device.allocator, image.image, image.allocation)
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
