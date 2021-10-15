#include <Spark/Renderer/FrameStats.h>

FrameStats* FrameStats::Get()
{
	static FrameStats stats = {};
	return &stats;
}