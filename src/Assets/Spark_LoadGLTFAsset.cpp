#include <Spark/Assets/Spark_Asset.h>

#include <Spark/World/Spark_Entity.h>

#include <Spark/Renderer/Spark_Material.h>
#include <Spark/Renderer/Spark_Texture.h>
#include <Spark/Renderer/Spark_Renderer.h>
#include <Spark/Renderer/Spark_FrameStats.h>

#include <Spark/Core/Spark_Utils.h>

#include <Beard/Array.h>
#include <Beard/Math.h>
#include <Beard/Timer.h>

#include <entt/entt.hpp>

#define TINYGLTF_IMPLEMENTATION
#define TINYGLTF_NOEXCEPTION
#define JSON_NOEXCEPTION
#include <tiny_gltf.h>

#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <string>
#include <filesystem>
#include <stdio.h>

namespace gltf = tinygltf;

void LoadMesh(u32 meshIndex, const gltf::Model& input, Entity entity)
{
	const auto& inputMesh = input.meshes[meshIndex];

	if (!inputMesh.name.empty())
	{
		entity.AddComponent<NameComponent>(inputMesh.name);
	}

	if (inputMesh.primitives.size() > 1)
	{
		// TODO
		ASSERT_UNREACHABLE();
	}

	ASSERT(!inputMesh.primitives.empty(), "No primitive ???");

	if (inputMesh.primitives.empty())
	{
		return;
	}

	auto& renderable = entity.AddComponent<Renderable>();

	const auto& primitive = inputMesh.primitives[0];

	// Load primitive's material
	const auto& inputMaterial    = input.materials[primitive.material];
	const auto& inputPBRMaterial = inputMaterial.pbrMetallicRoughness;
	auto        material         = std::make_shared<Material>(inputMaterial.name.c_str(), "pbr.vert.glsl", "pbr.frag.glsl");

	material->albedo         = glm::make_vec3(inputPBRMaterial.baseColorFactor.data());
	material->roughness      = inputPBRMaterial.roughnessFactor;
	material->metallic       = inputPBRMaterial.metallicFactor;
	material->emissive       = glm::make_vec3(inputMaterial.emissiveFactor.data());
	material->emissiveFactor = 1.0f;
	material->hasEmissive    = true;

	auto GetTexture = [&input](i32 index) -> u32
	{
		if (index == -1)
		{
			return 0;
		}

		const auto& texture = input.textures[index];
		const auto& image   = input.images[texture.source];
		const auto& sampler = input.samplers[texture.sampler];
		ASSERT(!image.image.empty(), "Empty image -> TODO");
		ASSERT(image.bufferView == -1, "Has a buffer -> TODO");

		u32 result = LoadTexture(image.width, image.height, image.component, image.image.data());
		return result;
	};

	if (u32 texture = GetTexture(inputPBRMaterial.baseColorTexture.index); texture != 0)
	{
		material->albedoTexture    = texture;
		material->hasAlbedoTexture = true;
	}

	if (u32 texture = GetTexture(inputPBRMaterial.metallicRoughnessTexture.index); texture != 0)
	{
		material->metallicRoughnessTexture    = texture;
		material->hasMetallicRoughnessTexture = true;
	}

	if (u32 texture = GetTexture(inputMaterial.emissiveTexture.index); texture != 0)
	{
		material->emissiveTexture    = texture;
		material->hasEmissiveTexture = true;
	}

	if (u32 texture = GetTexture(inputMaterial.normalTexture.index); texture != 0)
	{
		material->normalMap    = texture;
		material->hasNormalMap = true;
	}

	if (u32 texture = GetTexture(inputMaterial.occlusionTexture.index); texture != 0)
	{
		material->ambientOcclusionMap    = texture;
		material->hasAmbientOcclusionMap = true;
	}

	// TODO: Alpha mode

	// Load primitive's geometry
	Mesh mesh = {};

	// Index infos
	const auto& indexAccessor   = input.accessors[primitive.indices];
	const auto& indexBufferView = input.bufferViews[indexAccessor.bufferView];
	usize       indexOffset     = indexAccessor.byteOffset + indexBufferView.byteOffset;
	usize       indexCount      = indexAccessor.count;
	IndexType   indexType       = indexAccessor.componentType == TINYGLTF_COMPONENT_TYPE_UNSIGNED_SHORT ? IndexType::Unsigned16
	                                                                                                    : IndexType::Unsigned32;
	i32         indexStride     = indexType == IndexType::Unsigned16 ? 2 : 4;
	i32         indexLength     = indexCount * indexStride;

	mesh.indices.Resize(indexLength);
	memcpy(mesh.indices.Data(), input.buffers[indexBufferView.buffer].data.data() + indexOffset, indexLength);

	for (auto attribute : primitive.attributes)
	{
		const auto& attributeAccessor   = input.accessors[attribute.second];
		const auto& attributeBufferView = input.bufferViews[attributeAccessor.bufferView];
		const auto& attributeBuffer     = input.buffers[attributeBufferView.buffer];
		usize       attributeCount      = attributeAccessor.count;
		usize       attributeOffset     = attributeAccessor.byteOffset + attributeBufferView.byteOffset;
		usize       attributeLength     = attributeBufferView.byteLength - attributeAccessor.byteOffset; // Is this true ?
		usize       attributeStride     = attributeBufferView.byteStride;

		if (attribute.first == "POSITION")
		{
			mesh.positions.Resize(attributeCount);
			memcpy(mesh.positions.Data(), attributeBuffer.data.data() + attributeOffset, mesh.positions.DataSize());
		}
		else if (attribute.first == "NORMAL")
		{
			mesh.normals.Resize(attributeCount);
			memcpy(mesh.normals.Data(), attributeBuffer.data.data() + attributeOffset, mesh.normals.DataSize());
		}
		else if (attribute.first == "TEXCOORD_0")
		{
			mesh.texcoords.Resize(attributeCount);
			memcpy(mesh.texcoords.Data(), attributeBuffer.data.data() + attributeOffset, mesh.texcoords.DataSize());
		}
		else if (attribute.first == "TEXCOORD_1")
		{
			// TODO
		}
		else if (attribute.first == "TANGENT")
		{
			// Ignore
		}
		else
		{
			ASSERT_UNREACHABLE();
		}
	}

	mesh.indexType   = indexType;
	mesh.indexCount  = indexCount;
	mesh.vertexCount = mesh.positions.ElementCount();

	auto renderMesh = std::make_shared<RenderMesh>(std::move(mesh));

	renderable.material = material;
	renderable.mesh     = renderMesh;
}

void LoadNode(u32 nodeIndex, const gltf::Model& input, const glm::mat4& parentTransform, World* world)
{
	const auto& node = input.nodes[nodeIndex];

	glm::mat4 localTransform = glm::mat4{1.0f};

	if (!node.matrix.empty())
	{
		localTransform = glm::make_mat4(node.matrix.data());
	}
	else
	{
		glm::mat4 T = glm::mat4{1.0f};
		glm::mat4 R = glm::mat4{1.0f};
		glm::mat4 S = glm::mat4{1.0f};

		if (!node.translation.empty())
		{
			auto translation = glm::vec3{node.translation[0], node.translation[1], node.translation[2]};
			T                = glm::translate(T, translation);
		}

		if (!node.rotation.empty())
		{
			auto rotation = glm::quat{static_cast<f32>(node.rotation[3]),
			                          static_cast<f32>(node.rotation[0]),
			                          static_cast<f32>(node.rotation[1]),
			                          static_cast<f32>(node.rotation[2])};
			R             = glm::mat4_cast(rotation);
		}

		if (!node.scale.empty())
		{
			auto scale = glm::vec3{node.scale[0], node.scale[1], node.scale[2]};
			S          = glm::scale(S, scale);
		}

		localTransform = T * R * S;
	}

	// TODO: This is already broken. We cannot really flatten the scenegraph as we might have animations
	// that touch a parent node of a mesh.
	glm::mat4 worldTransform = parentTransform * localTransform;

	if (node.mesh != -1)
	{
		auto entity = world->CreateEntity();
		LoadMesh(node.mesh, input, entity);
		entity.SetTransform(worldTransform);

		if (!node.name.empty())
		{
			entity.AddComponent<NameComponent>(node.name);
		}
	}

	if (node.skin != -1)
	{
		// TODO
	}

	if (node.camera != -1)
	{
		// TODO
	}

	for (u32 childIndex : node.children)
	{
		LoadNode(childIndex, input, worldTransform, world);
	}
}

void LoadScene(const gltf::Model& input, World* world)
{
	const auto& scene = input.scenes[input.defaultScene];

	for (u32 nodeIndex : scene.nodes)
	{
		LoadNode(nodeIndex, input, glm::mat4{1.0f}, world);
	}
}

bool LoadGLTFScene(const char* filename, World* world)
{
	gltf::TinyGLTF loader;
	gltf::Model    scene;
	std::string    err;
	std::string    warn;

	bool ok  = false;
	auto ext = std::string(filename).substr(std::string(filename).find_last_of(".") + 1);

	if (ext == "gltf")
	{
		ok = loader.LoadASCIIFromFile(&scene, &err, &warn, filename);
	}
	else if (ext == "glb")
	{
		ok = loader.LoadBinaryFromFile(&scene, &err, &warn, filename);
	}
	else
	{
		ASSERT_UNREACHABLE();
	}

	if (!warn.empty())
	{
		fprintf(stderr, "GLTF Loader warning: %s\n", warn.c_str());
	}

	if (!err.empty())
	{
		fprintf(stderr, "GLTF Loader error: %s\n", err.c_str());
	}

	if (!ok)
	{
		fprintf(stderr, "Failed to load GLTF \"%s\"\n", filename);
		return false;
	}

	LoadScene(scene, world);

	return true;
}