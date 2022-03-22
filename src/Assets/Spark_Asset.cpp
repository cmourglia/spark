#include <Spark/Assets/Spark_Asset.h>

#include <Spark/Renderer/Spark_FrameStats.h>

#include <beard/misc/timer.h>

#include <string>

extern bool LoadAssimpScene(const char* filename, World* world);
extern bool LoadGLTFScene(const char* filename, World* world);

bool LoadScene(const char* filename, World* world)
{
	beard::timer timer;

	bool result = false;

	auto ext = std::string(filename).substr(std::string(filename).find_last_of(".") + 1);
	if (ext == "gltf" || ext == "glb")
	{
		timer.restart();
		result = LoadGLTFScene(filename, world);
	}
	else
	{
		timer.restart();
		result = LoadAssimpScene(filename, world);
	}

	FrameStats::Get()->loadScene = timer.tick();

	return result;
}
