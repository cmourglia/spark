package spark

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import gltf "shared:glTF2"
import vk "vendor:vulkan"

Vertex :: struct {
	position: glm.vec3,
	uvX:      f32,
	normal:   glm.vec3,
	uvY:      f32,
	color:    glm.vec4,
}

GpuMeshBuffers :: struct {
	indexBuffer:         Buffer,
	vertexBuffer:        Buffer,
	vertexBufferAddress: vk.DeviceAddress,
}

GeoSurface :: struct {
	startIndex: u32,
	count:      u32,
}

MeshAsset :: struct {
	name:        string,
	surfaces:    [dynamic]GeoSurface,
	meshBuffers: GpuMeshBuffers,
}

LoadGltf :: proc(ctx: ^ImmediateContext, filepath: string) -> ([]MeshAsset, bool) {
	data, error := gltf.load_from_file(filepath)

	if error != nil {
		return nil, false
	}
	defer gltf.unload(data)

	meshes: [dynamic]MeshAsset

	indices := make([dynamic]u32, context.temp_allocator)
	vertices := make([dynamic]Vertex, context.temp_allocator)

	for mesh in data.meshes {
		meshAsset: MeshAsset
		meshAsset.name = mesh.name.? or_else "[no name]"

		clear(&indices)
		clear(&vertices)

		for p in mesh.primitives {
            fmt.printf("%v\n", p.attributes)
			newSurface := GeoSurface {
				startIndex = u32(len(indices)),
				count      = u32(data.accessors[p.indices.?].count),
			}

            append(&meshAsset.surfaces, newSurface)

			initialVertex := u32(len(vertices))

			{
				indexAccessor := data.accessors[p.indices.?]
				reserve(&indices, int(indexAccessor.count) + len(indices))
				for it := gltf.buf_iter_make(u16, &indexAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					append(&indices, u32(gltf.buf_iter_elem(&it)))
				}
			}

			{
				vertexAccessor := data.accessors[p.attributes["POSITION"]]
				reserve(&vertices, int(vertexAccessor.count) + len(vertices))
				for it := gltf.buf_iter_make(glm.vec3, &vertexAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertex := Vertex {
						position = gltf.buf_iter_elem(&it),
						uvX      = 0,
						normal   = {},
						uvY      = 0,
						color    = {1, 1, 1, 1},
					}
					append(&vertices, vertex)
				}
			}

			if normals, has_normals := p.attributes["NORMAL"]; has_normals {
				normalAccessor := data.accessors[normals]
				for it := gltf.buf_iter_make(glm.vec3, &normalAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertices[initialVertex + it.idx].normal = gltf.buf_iter_elem(&it)
				}
			} else {
				log.info("No normals found")
			}

			if texcoords, has_texcoords := p.attributes["TEXCOORD_0"]; has_texcoords {
				texcoordAccessor := data.accessors[texcoords]
				for it := gltf.buf_iter_make(glm.vec2, &texcoordAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					uv := gltf.buf_iter_elem(&it)
					vertices[initialVertex + it.idx].uvX = uv.x
					vertices[initialVertex + it.idx].uvY = uv.y
				}
			} else {
				log.info("No texcoords found")
			}

			if colors, has_colors := p.attributes["COLOR_0"]; has_colors {
				colorAccessor := data.accessors[colors]
				for it := gltf.buf_iter_make(glm.vec4, &colorAccessor, data);
				    it.idx < it.count;
				    it.idx += 1 {
					vertices[initialVertex + it.idx].color = gltf.buf_iter_elem(&it)
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

        meshAsset.meshBuffers = UploadMesh(ctx, indices[:], vertices[:])
        append(&meshes, meshAsset)
	}

	return meshes[:], true
}

DeleteMeshAsset::proc(device: Device, meshAsset: MeshAsset)
{
    DestroyBuffer(device, meshAsset.meshBuffers.vertexBuffer)
    DestroyBuffer(device, meshAsset.meshBuffers.indexBuffer)

    delete(meshAsset.surfaces)
}
