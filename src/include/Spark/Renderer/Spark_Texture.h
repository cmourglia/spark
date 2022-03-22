#pragma once

#include <beard/core/macros.h>

#include <string>

u32 LoadTexture(const std::string& filename);
u32 LoadTexture(i32 width, i32 height, i32 components, const u8* data);