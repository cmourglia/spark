package spark

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import gltf "shared:glTF2"
import vk "vendor:vulkan"

Vertex :: struct {
	position: glm.vec3,
	uv_x:     f32,
	normal:   glm.vec3,
	uv_y:     f32,
	color:    glm.vec4,
}

Gpu_Mesh_Buffers :: struct {
	index_buffer:          Buffer,
	vertex_buffer:         Buffer,
	vertex_buffer_address: vk.DeviceAddress,
}

Geo_Surface :: struct {
	start_index: u32,
	count:       u32,
}

Mesh_Asset :: struct {
	name:         string,
	surfaces:     [dynamic]Geo_Surface,
	mesh_buffers: Gpu_Mesh_Buffers,
}

load_gltf :: proc(ctx: ^Immediate_Context, filepath: string) -> ([]Mesh_Asset, bool) {
	data, error := gltf.load_from_file(filepath)

	if error != nil {
		return nil, false
	}
	defer gltf.unload(data)

	meshes: [dynamic]Mesh_Asset

	indices := make([dynamic]u32, context.temp_allocator)
	vertices := make([dynamic]Vertex, context.temp_allocator)

	for mesh in data.meshes {
		mesh_asset: Mesh_Asset
		mesh_asset.name = mesh.name.? or_else "[no name]"

		clear(&indices)
		clear(&vertices)

		for p in mesh.primitives {
			fmt.printf("%v\n", p.attributes)
			new_surface := Geo_Surface {
				start_index = u32(len(indices)),
				count       = u32(data.accessors[p.indices.?].count),
			}

			append(&mesh_asset.surfaces, new_surface)

			initial_vertex := u32(len(vertices))

			{
				index_accessor := data.accessors[p.indices.?]
				reserve(&indices, int(index_accessor.count) + len(indices))
				for it := gltf.buf_iter_make(u16, &index_accessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					append(&indices, u32(gltf.buf_iter_elem(&it)))
				}
			}

			{
				vertex_accessor := data.accessors[p.attributes["POSITION"]]
				reserve(&vertices, int(vertex_accessor.count) + len(vertices))
				for it := gltf.buf_iter_make(glm.vec3, &vertex_accessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertex := Vertex {
						position = gltf.buf_iter_elem(&it),
						uv_x     = 0,
						normal   = {},
						uv_y     = 0,
						color    = {1, 1, 1, 1},
					}
					append(&vertices, vertex)
				}
			}

			if normals, has_normals := p.attributes["NORMAL"]; has_normals {
				normal_accessor := data.accessors[normals]
				for it := gltf.buf_iter_make(glm.vec3, &normal_accessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertices[initial_vertex + it.idx].normal = gltf.buf_iter_elem(&it)
				}
			} else {
				log.info("No normals found")
			}

			if texcoords, has_texcoords := p.attributes["TEXCOORD_0"]; has_texcoords {
				texcoord_accessors := data.accessors[texcoords]
				for it := gltf.buf_iter_make(glm.vec2, &texcoord_accessors, data);
				    it.idx < it.count;
				    it.idx += 1 {
					uv := gltf.buf_iter_elem(&it)
					vertices[initial_vertex + it.idx].uv_x = uv.x
					vertices[initial_vertex + it.idx].uv_y = uv.y
				}
			} else {
				log.info("No texcoords found")
			}

			if colors, has_colors := p.attributes["COLOR_0"]; has_colors {
				colorAccessor := data.accessors[colors]
				for it := gltf.buf_iter_make(glm.vec4, &colorAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertices[initial_vertex + it.idx].color = gltf.buf_iter_elem(&it)
				}
			} else {
				log.info("No colors found")
			}
		}

		OVERRIDE_COLORS :: true

		when OVERRIDE_COLORS {
			for &vertex in vertices {
				vertex.color = {vertex.normal.x, vertex.normal.y, vertex.normal.z, 1}
			}
		}

		mesh_asset.mesh_buffers = upload_mesh(ctx, indices[:], vertices[:])
		append(&meshes, mesh_asset)
	}

	return meshes[:], true
}

delete_mesh_asset :: proc(device: Device, meshAsset: Mesh_Asset) {
	destroy_buffer(device, meshAsset.mesh_buffers.vertex_buffer)
	destroy_buffer(device, meshAsset.mesh_buffers.index_buffer)

	delete(meshAsset.surfaces)
}
