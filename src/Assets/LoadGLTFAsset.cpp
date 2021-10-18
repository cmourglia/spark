#include <Spark/Assets/Asset.h>

#include <Spark/World/Entity.h>

#include <Spark/Renderer/Material.h>
#include <Spark/Renderer/Texture.h>
#include <Spark/Renderer/Renderer.h>
#include <Spark/Renderer/FrameStats.h>

#include <Spark/Core/Utils.h>

#include <Beard/Timer.h>
#include <Beard/Array.h>

#include <entt/entt.hpp>

#define TINYGLTF_IMPLEMENTATION
#define TINYGLTF_NOEXCEPTION
#define JSON_NOEXCEPTION
#include <tiny_gltf.h>

#include <string>
#include <filesystem>

void LoadModel(const tinygltf::Model& model, World* world)
{
	UNUSED(model);
	UNUSED(world);

	BEARD_TODO(__FUNCTION__);
}

bool LoadGLTFScene(const char* filename, World* world)
{
	tinygltf::TinyGLTF loader;
	tinygltf::Model    model;
	std::string        err;
	std::string        warn;

	bool ok = loader.LoadASCIIFromFile(&model, &err, &warn, filename);

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

	LoadModel(model, world);

	return true;
}