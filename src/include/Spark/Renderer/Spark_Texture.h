#pragma once

#include <Beard/Macros.h>
#include <Beard/Array.h>

#include <string>

u32 LoadTexture(const std::string& filename);
u32 LoadTexture(i32 width, i32 height, i32 components, const u8* data);