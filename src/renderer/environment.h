#pragma once

#include "core/defines.h"

struct Environment
{
	u32 envMap;
	u32 irradianceMap;
	u32 radianceMap;
	u32 iblDFG;
};

void LoadEnvironment(const char* filename, Environment* env);