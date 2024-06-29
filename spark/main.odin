package spark

import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:mem"
import im "shared:odin-imgui"
import "shared:odin-imgui/imgui_impl_glfw"
import "shared:odin-imgui/imgui_impl_vulkan"
import glfw "vendor:glfw"

import "./raytracer"

main :: proc() {
	context.logger = log.create_console_logger()
	g_ctx = context

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	run()

	for _, leak in track.allocation_map {
		fmt.printf("%v leaked %m\n", leak.location, leak.size)
	}
	for bad_free in track.bad_free_array {
		fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
	}
}

run :: proc() {
	ctx := Context{}

	init_window(&ctx)
	defer deinit_window(&ctx)

	init_vulkan(&ctx)
	defer deinit_vulkan(&ctx)

	raytracer.launch(ctx.raytraced_image_data, {ctx.draw_extent.width, ctx.draw_extent.height})
    defer raytracer.cleanup()

	for !glfw.WindowShouldClose(ctx.window) {
		glfw.PollEvents()

		if resize_if_necessary(&ctx) {
			raytracer.resize(
				ctx.raytraced_image_data,
				{ctx.draw_extent.width, ctx.draw_extent.height},
			)
		}

		imgui_impl_vulkan.NewFrame()
		imgui_impl_glfw.NewFrame()

		im.NewFrame()

		if im.Begin("background") {
			effect := &ctx.compute_effects[ctx.current_effect]

			im.Text("Selected effect: ", effect.name)

			im.SliderInt("Effect index", &ctx.current_effect, 0, i32(len(ctx.compute_effects) - 1))

			im.InputFloat4("data1", cast(^[4]f32)&effect.data.data1)
			im.InputFloat4("data2", cast(^[4]f32)&effect.data.data2)
			im.InputFloat4("data3", cast(^[4]f32)&effect.data.data3)
			im.InputFloat4("data4", cast(^[4]f32)&effect.data.data4)
		}
		im.End()

		im.Render()

		draw(&ctx)
	}
}
