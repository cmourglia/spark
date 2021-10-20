#include <Spark/Assets/Spark_Asset.h>

#include <Spark/World/Spark_Entity.h>

#include <Spark/Renderer/Spark_Material.h>
#include <Spark/Renderer/Spark_Texture.h>
#include <Spark/Renderer/Spark_Mesh.h>
#include <Spark/Renderer/Spark_Renderer.h>
#include <Spark/Renderer/Spark_FrameStats.h>

#include <Spark/Core/Spark_Utils.h>

#include <Beard/Timer.h>
#include <Beard/Array.h>
#include <Beard/Math.h>

#include <entt/entt.hpp>

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <assimp/pbrmaterial.h>

#include <string>
#include <filesystem>

inline std::string TexturePath(const char* texture, const std::filesystem::path& path)
{
	std::filesystem::path texturePath(texture);
	if (texturePath.is_absolute())
	{
		return texturePath.string();
	}

	std::filesystem::path fullPath = path / texturePath;

	return fullPath.string();
}

inline std::shared_ptr<Material> ProcessMaterial(aiMaterial* inputMaterial, const aiScene* scene, const std::filesystem::path& path)
{
	auto material = std::make_shared<Material>(inputMaterial->GetName().C_Str(), "pbr.vert.glsl", "pbr.frag.glsl");

	aiColor3D albedo;
	if (AI_SUCCESS == inputMaterial->Get(AI_MATKEY_BASE_COLOR, albedo))
	{
		material->albedo = glm::vec3(albedo.r, albedo.g, albedo.b);
	}

	f32 metallic;
	if (AI_SUCCESS == inputMaterial->Get(AI_MATKEY_METALLIC_FACTOR, metallic))
	{
		material->metallic = metallic;
	}

	f32 roughness;
	if (AI_SUCCESS == inputMaterial->Get(AI_MATKEY_ROUGHNESS_FACTOR, roughness))
	{
		material->roughness = roughness;
	}

	aiString albedoTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(AI_MATKEY_BASE_COLOR_TEXTURE, &albedoTexture))
	{
		material->hasAlbedoTexture = true;
		material->albedoTexture    = LoadTexture(TexturePath(albedoTexture.C_Str(), path));
	}

	aiString metallicTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(AI_MATKEY_METALLIC_TEXTURE, &metallicTexture))
	{
		material->hasMetallicTexture = true;
		material->metallicTexture    = LoadTexture(TexturePath(metallicTexture.C_Str(), path));
	}

	aiString roughnessTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(AI_MATKEY_ROUGHNESS_TEXTURE, &roughnessTexture))
	{
		material->hasRoughnessTexture = true;
		material->roughnessTexture    = LoadTexture(TexturePath(roughnessTexture.C_Str(), path));
	}

	aiString metallicRoughnessTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(AI_MATKEY_GLTF_PBRMETALLICROUGHNESS_METALLICROUGHNESS_TEXTURE, &metallicRoughnessTexture))
	{
		material->hasMetallicRoughnessTexture = true;
		material->metallicRoughnessTexture    = LoadTexture(TexturePath(metallicRoughnessTexture.C_Str(), path));
	}

	aiColor3D emissiveColor;
	if (AI_SUCCESS == inputMaterial->Get(AI_MATKEY_COLOR_EMISSIVE, emissiveColor))
	{
		material->hasEmissive = true;
		material->emissive    = glm::vec3(emissiveColor.r, emissiveColor.g, emissiveColor.b);
	}

	aiString emissiveTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(aiTextureType_EMISSIVE, 0, &emissiveTexture))
	{
		material->hasEmissiveTexture = true;
		material->emissiveTexture    = LoadTexture(TexturePath(emissiveTexture.C_Str(), path));
	}

	aiString occlusionTexture;
	if (AI_SUCCESS == inputMaterial->GetTexture(aiTextureType_LIGHTMAP, 0, &occlusionTexture))
	{
		material->hasAmbientOcclusionMap = true;
		material->ambientOcclusionMap    = LoadTexture(TexturePath(occlusionTexture.C_Str(), path));
	}

	return material;
}

std::shared_ptr<RenderMesh> ProcessMesh(aiMesh* inputMesh, const aiScene* scene)
{
	Mesh mesh = {};

	mesh.positions.Resize(inputMesh->mNumVertices);
	mesh.normals.Resize(inputMesh->mNumVertices);
	mesh.texcoords.Reserve(inputMesh->mNumVertices);

	mesh.indices.Resize(inputMesh->mNumFaces * 3 * sizeof(u32));

	mesh.vertexCount = inputMesh->mNumVertices;
	mesh.indexCount  = inputMesh->mNumFaces * 3;
	mesh.indexType   = IndexType::Unsigned32;

	const aiVector3D* inVertices  = inputMesh->mVertices;
	const aiVector3D* inNormals   = inputMesh->mNormals;
	const aiVector3D* inTexcoords = inputMesh->mTextureCoords[0];

	memcpy(mesh.positions.Data(), inVertices, mesh.positions.DataSize());
	memcpy(mesh.normals.Data(), inNormals, mesh.normals.DataSize());

	if (inTexcoords != nullptr)
	{
		for (u32 i = 0; i < inputMesh->mNumVertices; ++i)
		{
			aiVector3D texcoord = inTexcoords[i];
			mesh.texcoords.Add({texcoord.x, texcoord.y});
		}
	}

	u32* indices = (u32*)mesh.indices.Data();

	const aiFace* inFaces = inputMesh->mFaces;
	for (u32 i = 0; i < inputMesh->mNumFaces; ++i)
	{
		aiFace face = inFaces[i];

		indices[i * 3 + 0] = face.mIndices[0];
		indices[i * 3 + 1] = face.mIndices[1];
		indices[i * 3 + 2] = face.mIndices[2];
	}

	auto renderMesh = std::make_shared<RenderMesh>(std::move(mesh));

	return renderMesh;
}

inline void ProcessNode(aiNode*                      node,
                        const aiScene*               scene,
                        const glm::mat4&             parentTransform,
                        const std::filesystem::path& path,
                        World*                       world)
{
	const auto& mat = node->mTransformation;

	// clang-format off
	const glm::mat4 nodeTransform(mat.a1, mat.b1, mat.c1, mat.d1,
	                              mat.a2, mat.b2, mat.c2, mat.d2,
	                              mat.a3, mat.b3, mat.c3, mat.d3,
	                              mat.a4, mat.b4, mat.c4, mat.d4);
	// clang-format on

	const glm::mat4 worldTransform = parentTransform * nodeTransform;

	for (u32 index = 0; index < node->mNumMeshes; ++index)
	{
		aiMesh*     inputMesh     = scene->mMeshes[node->mMeshes[index]];
		aiMaterial* inputMaterial = scene->mMaterials[inputMesh->mMaterialIndex];

		auto entity = world->CreateEntity();

		auto& renderable    = entity.AddComponent<Renderable>();
		renderable.mesh     = ProcessMesh(scene->mMeshes[node->mMeshes[index]], scene);
		renderable.material = ProcessMaterial(inputMaterial, scene, path);

		entity.SetTransform(std::move(worldTransform));

		entity.AddComponent<NameComponent>().name = node->mName.C_Str();
	}

	for (u32 index = 0; index < node->mNumChildren; ++index)
	{
		ProcessNode(node->mChildren[index], scene, worldTransform, path, world);
	}
}

bool LoadAssimpScene(const char* filename, World* world)
{
	Assimp::Importer importer;

	const u32 importerFlags = aiProcess_Triangulate | aiProcess_GenSmoothNormals | aiProcess_CalcTangentSpace | aiProcess_OptimizeMeshes;
	const aiScene* scene    = importer.ReadFile(filename, importerFlags);

	if ((nullptr == scene) || (0 != (scene->mFlags & AI_SCENE_FLAGS_INCOMPLETE)) || (nullptr == scene->mRootNode))
	{
		fprintf(stderr, "Could not load file %s\n", filename);
		return false;
	}

	std::filesystem::path p;
	p = filename;
	p.remove_filename();
	ProcessNode(scene->mRootNode, scene, glm::mat4(1.0f), p, world);

	return true;
}