#include <Spark/Renderer/Spark_FrameStats.h>

FrameStats* FrameStats::Get()
{
	static FrameStats stats = {};
	return &stats;
}