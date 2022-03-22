#pragma once

#include <beard/core/macros.h>

struct GLFWwindow;
struct World;

namespace UI {
void Setup(GLFWwindow* window);
void Resize(u32 width, u32 height);
void UpdateAndRender(World* world);

void ClearSelection();
bool IsCursorInViewport(f64 x, f64 y);
}  // namespace UI