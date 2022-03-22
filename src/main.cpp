#include <beard/core/macros.h>

#include <Spark/Core/Spark_Utils.h>

#include <Spark/Renderer/Spark_Program.h>
#include <Spark/Renderer/Spark_Material.h>
#include <Spark/Renderer/Spark_Environment.h>
#include <Spark/Renderer/Spark_RenderPrimitives.h>
#include <Spark/Renderer/Spark_Renderer.h>
#include <Spark/Renderer/Spark_Texture.h>
#include <Spark/Renderer/Spark_FrameStats.h>

#include <Spark/Assets/Spark_Asset.h>

#include <Spark/World/Spark_World.h>
#include <Spark/World/Spark_Entity.h>

#include <Beard/Array.h>
#include <Beard/HashMap.h>
#include <Beard/Math.h>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include <imgui.h>
#include <imgui_internal.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include "imfilebrowser.h"

#include <filesystem>
#include <chrono>
#include <unordered_set>
#include <filesystem>

#include <stdio.h>

static void MouseButtonCallback(GLFWwindow* window, i32 button, i32 action, i32 mods);
static void MouseMoveCallback(GLFWwindow* window, f64 x, f64 y);
static void KeyCallback(GLFWwindow* window, i32 key, i32 scancode, i32 action, i32 mods);
static void WheelCallback(GLFWwindow* window, f64 x, f64 y);

static void FramebufferSizeCallback(GLFWwindow* window, i32 width, i32 height);

static void DropCallback(GLFWwindow* window, i32 count, const char** paths);

void DebugOutput(GLenum source, GLenum type, u32 id, GLenum severity, GLsizei length, const char* message, const void* userParam);

static i32 g_Width, g_Height;

std::string GetFileExtension(const std::string& filename)
{
	return filename.substr(filename.find_last_of(".") + 1);
}

struct OrbitCamera
{
	f32 phi      = 45.0f;
	f32 theta    = 45.0f;
	f32 distance = 7.5f;

	glm::vec3 position;
	glm::vec3 center = glm::vec3(0.0f, 0.0f, 0.0f);
	glm::vec3 up     = glm::vec3(0.0f, 1.0f, 0.0f);

	glm::mat4 GetView()
	{
		using beard::math::DegToRad;
		const f32 x = distance * sinf(theta * DegToRad) * sinf(phi * DegToRad);
		const f32 y = distance * cosf(theta * DegToRad);
		const f32 z = distance * sinf(theta * DegToRad) * cosf(phi * DegToRad);

		position = glm::vec3(x, y, z) + center;

		return glm::lookAt(position, center, up);
	}
};

void SetupUI(GLFWwindow* window);
void RenderUI(const std::vector<Model>& models);

global_variable beard::hash_map<u32, Program> g_Programs;

global_variable OrbitCamera g_Camera;
//  global_variable f32    g_lastScroll = 0.0f;
global_variable f32 g_ViewportX = 0.0f, g_ViewportY = 0.0f;
global_variable f32 g_ViewportW = 0.0f, g_ViewportH = 0.0f;

global_variable World g_World;

global_variable Environment* g_Env = nullptr;

i32 main()
{
	glfwInit();

	glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
	glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_FALSE);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
	glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
	// TODO: Proper multisampling
	// glfwWindowHint(GLFW_SAMPLES, 8);
#if _DEBUG
	glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GLFW_TRUE);
#endif

	GLFWwindow* window = glfwCreateWindow(1920, 1080, "Viewer", nullptr, nullptr);

	glfwSetKeyCallback(window, KeyCallback);
	glfwSetMouseButtonCallback(window, MouseButtonCallback);
	glfwSetCursorPosCallback(window, MouseMoveCallback);
	glfwSetScrollCallback(window, WheelCallback);
	glfwSetFramebufferSizeCallback(window, FramebufferSizeCallback);
	glfwSetDropCallback(window, DropCallback);

	glfwMakeContextCurrent(window);
	glfwSwapInterval(1);

	glfwGetFramebufferSize(window, &g_Width, &g_Height);

	if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))
	{
		return 1;
	}

#if _DEBUG
	glEnable(GL_DEBUG_OUTPUT);
	glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
	glDebugMessageCallback(DebugOutput, nullptr);
	glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, 0, nullptr, GL_TRUE);
#endif

	SetupUI(window);

	Renderer& renderer = Renderer::Get();
	renderer.Initialize(glm::vec2(g_Width, g_Height));

	g_Env = &renderer.env;

	LoadEnvironment("resources/env/Frozen_Waterfall_Ref.hdr", g_Env);

	// LoadScene(R"(external\glTF-Sample-Models\2.0\MetalRoughSpheres\glTF\MetalRoughSpheres.gltf, &g_World)");
	// LoadScene(R"(resources/models/blender_probe/probe.glb)", &g_World);
	// LoadScene(R"(resources/models/3spheres.glb)", &g_World);
	// LoadScene(R"(external\glTF-Sample-Models\2.0\AnimatedCube\glTF\AnimatedCube.gltf)", &g_World);

	// LoadScene(R"(external\glTF-Sample-Models\2.0\Box\glTF\Box.gltf)", &g_World);
	LoadScene(R"(external\glTF-Sample-Models\2.0\Cube\glTF\Cube.gltf)", &g_World);
	// LoadScene(R"(external\glTF-Sample-Models\2.0\DamagedHelmet\glTF\DamagedHelmet.gltf, &g_World)");
	// LoadScene(R"(external\glTF-Sample-Models\2.0\SimpleSkin\glTF\SimpleSkin.gltf)", &g_World);

	ImGui::FileBrowser textureDialog;
	textureDialog.SetTitle("Open texture...");
	textureDialog.SetTypeFilters({".png", ".jpg", ".jpeg", ".tiff"});

	static glm::vec2 lastSize(0, 0);

	auto  cameraEntity    = g_World.CreateEntity();
	auto& cameraComponent = cameraEntity.AddComponent<CameraComponent>();

	while (!glfwWindowShouldClose(window))
	{
		cameraEntity.SetTransform(g_Camera.GetView());
		cameraComponent.position = g_Camera.position;

		if (lastSize.x != 0 && lastSize.y != 0)
		{
			g_World.Update();
		}

		ImGuiIO& io = ImGui::GetIO();

		ImGui_ImplOpenGL3_NewFrame();
		ImGui_ImplGlfw_NewFrame();
		ImGui::NewFrame();

		static ImGuiDockNodeFlags dockspace_flags = ImGuiDockNodeFlags_None;
		static GLuint*            selectedTexture;

		// We are using the ImGuiWindowFlags_NoDocking flag to make the parent window not dockable into,
		// because it would be confusing to have two docking targets within each others.
		ImGuiWindowFlags window_flags = ImGuiWindowFlags_MenuBar | ImGuiWindowFlags_NoDocking;
		ImGuiViewport*   viewport     = ImGui::GetMainViewport();
		ImGui::SetNextWindowPos(viewport->WorkPos);
		ImGui::SetNextWindowSize(viewport->WorkSize);
		ImGui::SetNextWindowViewport(viewport->ID);
		ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
		ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
		window_flags |= ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove;
		window_flags |= ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoNavFocus;

		// When using ImGuiDockNodeFlags_PassthruCentralNode, DockSpace() will render our background
		// and handle the pass-thru hole, so we ask Begin() to not render a background.
		if (dockspace_flags & ImGuiDockNodeFlags_PassthruCentralNode)
			window_flags |= ImGuiWindowFlags_NoBackground;

		// Important: note that we proceed even if Begin() returns false (aka window is collapsed).
		// This is because we want to keep our DockSpace() active. If a DockSpace() is inactive,
		// all active windows docked into it will lose their parent and become undocked.
		// We cannot preserve the docking relationship between an active window and an inactive docking, otherwise
		// any change of dockspace/settings would lead to windows being stuck in limbo and never being visible.
		ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
		ImGui::Begin("DockSpace Demo", nullptr, window_flags);
		ImGui::PopStyleVar();

		ImGui::PopStyleVar(2);

		// DockSpace
		// ImGuiIO& io = ImGui::GetIO();
		ImGuiID dockspace_id = ImGui::GetID("###Dockspace");

		if (ImGui::DockBuilderGetNode(dockspace_id) == nullptr)
		{
			ImGui::DockBuilderRemoveNode(dockspace_id);
			ImGui::DockBuilderAddNode(dockspace_id, ImGuiDockNodeFlags_DockSpace);
			ImGui::DockBuilderSetNodeSize(dockspace_id, ImVec2((f32)g_Width, (f32)g_Height));

			ImGuiID dockMainID  = dockspace_id;
			ImGuiID dockIDLeft  = ImGui::DockBuilderSplitNode(dockMainID, ImGuiDir_Left, 0.20f, nullptr, &dockMainID);
			ImGuiID dockIDRight = ImGui::DockBuilderSplitNode(dockMainID, ImGuiDir_Right, 0.20f, nullptr, &dockMainID);

			ImGui::DockBuilderDockWindow("Viewport", dockMainID);
			ImGui::DockBuilderDockWindow("Entities", dockIDLeft);
			ImGui::DockBuilderDockWindow("Light", dockIDLeft);
			ImGui::DockBuilderDockWindow("Properties", dockIDRight);
		}

		ImGui::DockSpace(dockspace_id, ImVec2(0.0f, 0.0f), dockspace_flags);
		{
			ImGui::Begin("Viewport");
			{
				ImVec2 vMin = ImGui::GetWindowContentRegionMin();
				ImVec2 vMax = ImGui::GetWindowContentRegionMax();

				vMin.x += ImGui::GetWindowPos().x;
				vMin.y += ImGui::GetWindowPos().y;
				vMax.x += ImGui::GetWindowPos().x;
				vMax.y += ImGui::GetWindowPos().y;

				i32 wx, wy;
				glfwGetWindowPos(window, &wx, &wy);

				vMin.x -= (f32)wx;
				vMin.y -= (f32)wy;
				vMax.x -= (f32)wx;
				vMax.y -= (f32)wy;

				g_ViewportX = vMin.x;
				g_ViewportY = vMin.y;
				g_ViewportW = vMax.x - vMin.x;
				g_ViewportH = vMax.y - vMin.y;

				glm::vec2 size(g_ViewportW, g_ViewportH);

				if (size != lastSize)
				{
					cameraComponent.proj = glm::perspective(60.0f * Beard::Math::DegToRad, (f32)size.x / size.y, 0.1f, 5000.0f);
					renderer.Resize(size);
					lastSize = size;
				}

				ImTextureID id;
				id = (void*)(intptr_t)renderer.outputTexture;
				ImGui::Image(id, ImVec2(size.x, size.y), ImVec2(0, 1), ImVec2(1, 0));
			}
			ImGui::End();

			static i32 selectedEntity = -1;

			ImGui::Begin("Entities");
			{
				const auto& view = g_World.GetRegistry().view<NameComponent>();

				for (i32 i = 0; i < view.size(); ++i)
				{
					if (ImGui::Selectable(view.get<NameComponent>(view[i]).name.c_str(), selectedEntity == i))
					{
						selectedEntity = i;
					}
				}
			}
			ImGui::End();

			ImGui::Begin("Light");
			{
				ImGui::Text("Background");
				// ImGui::RadioButton("None", &renderer.backgroundType, (int)BackgroundType::None);
				// ImGui::RadioButton("Cubemap", &renderer.backgroundType, (int)BackgroundType::Cubemap);
				// ImGui::RadioButton("Irradiance", &renderer.backgroundType, (int)BackgroundType::Irradiance);
				// ImGui::RadioButton("Radiance", &renderer.backgroundType, (int)BackgroundType::Radiance);

				if (renderer.backgroundType == BackgroundType::Radiance)
				{
					ImGui::SliderInt("Mip level", &renderer.backgroundMipLevel, 0, 8);
				}
			}
			ImGui::End();

			ImGui::Begin("Post-Process");
			{
				ImGui::Text("A post-process effect");

				ImGui::Separator();

				ImGui::Text("Bloom parameters");
				ImGui::Checkbox("Enabled", &renderer.bloom.enabled);
				ImGui::DragFloat("Threshold", &renderer.bloom.threshold, 0.1f, 0.0f, 10.0f, "%.1f");
				ImGui::DragFloat("Knee", &renderer.bloom.knee, 0.01f, 0.0f, 10.0f, "%.2f");
				ImGui::DragFloat("Intensity", &renderer.bloom.intensity, 0.1f, 0.0f, 10.0f, "%.1f");

				ImGui::Separator();

				ImGui::Text("Another post-process effect");
			}
			ImGui::End();

			ImGui::Begin("Properties");
			if (ImGui::CollapsingHeader("Material", ImGuiTreeNodeFlags_DefaultOpen))
			{
				// if (selectedEntity >= 0 && selectedEntity < g_scene.models.size())
				// {
				// 	Model*    model    = &g_scene.models[selectedEntity];
				// 	Material* material = model->material;

				// 	ImGui::ColorEdit3("Albedo", &material->albedo.x);

				// 	ImGui::Checkbox("Albedo texture", &material->hasAlbedoTexture);
				// 	if (material->hasAlbedoTexture)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->albedoTexture, ImVec2(64, 64), ImVec2(0, 1),
				// ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->albedoTexture;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	ImGui::SliderFloat("Roughness", &material->roughness, 0.0f, 1.0f);

				// 	ImGui::Checkbox("Roughness texture", &material->hasRoughnessTexture);
				// 	if (material->hasRoughnessTexture)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->roughnessTexture, ImVec2(64, 64), ImVec2(0,
				// 1), ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->roughnessTexture;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	ImGui::SliderFloat("Metallic", &material->metallic, 0.0f, 1.0f);

				// 	ImGui::Checkbox("Metallic texture", &material->hasMetallicTexture);
				// 	if (material->hasMetallicTexture)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->metallicTexture, ImVec2(64, 64), ImVec2(0, 1),
				// ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->metallicTexture;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	ImGui::Checkbox("Metallic - Roughness texture", &material->hasMetallicRoughnessTexture);
				// 	if (material->hasMetallicRoughnessTexture)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->metallicRoughnessTexture,
				// 		                       ImVec2(64, 64),
				// 		                       ImVec2(0, 1),
				// 		                       ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->metallicRoughnessTexture;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	ImGui::Checkbox("Emissive", &material->hasEmissive);
				// 	if (material->hasEmissive)
				// 	{
				// 		ImGui::ColorEdit3("Emissive", &material->emissive.x);
				// 	}

				// 	ImGui::Checkbox("Emissive texture", &material->hasEmissiveTexture);
				// 	if (material->hasEmissiveTexture)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->emissiveTexture, ImVec2(64, 64), ImVec2(0, 1),
				// ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->emissiveTexture;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	if (material->hasEmissive || material->hasEmissiveTexture)
				// 	{
				// 		ImGui::SliderFloat("Emissive factor", &material->emissiveFactor, 0.0f, 10.0f);
				// 	}

				// 	ImGui::Checkbox("Normal map", &material->hasNormalMap);
				// 	if (material->hasNormalMap)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->normalMap, ImVec2(64, 64), ImVec2(0, 1),
				// ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->normalMap;
				// 			textureDialog.Open();
				// 		}
				// 	}

				// 	ImGui::Checkbox("AO map", &material->hasAmbientOcclusionMap);
				// 	if (material->hasAmbientOcclusionMap)
				// 	{
				// 		if (ImGui::ImageButton((void*)(intptr_t)material->ambientOcclusionMap, ImVec2(64, 64), ImVec2(0,
				// 1), ImVec2(1, 0)))
				// 		{
				// 			selectedTexture = &material->ambientOcclusionMap;
				// 			textureDialog.Open();
				// 		}
				// 	}
				// }
			}
			ImGui::End();

			ImGui::Begin("Stats");
			{
				FrameStats* stats = FrameStats::Get();

				ImGui::Text("Startup");
				ImGui::Text("\tIBL");
				ImGui::Text("\t\tDFG Precompute: %.1lfms", stats->ibl.precomputeDFG);
				ImGui::Text("\t\tEnvironment total: %.1lfms", stats->ibl.total);
				ImGui::Text("\t\tLoad texture: %.1lfms", stats->ibl.loadTexture);
				ImGui::Text("\t\tGenerate cubemap: %.1lfms", stats->ibl.cubemap);
				ImGui::Text("\t\tPrefilter specular: %.1lfms", stats->ibl.prefilter);
				ImGui::Text("\t\tIrradiance convolution: %.1lfms", stats->ibl.irradiance);
				ImGui::Text("\tScene");
				ImGui::Text("\t\tLoad time: %.1lfms", stats->loadScene);

				ImGui::Separator();

				ImGui::Text("Frame");
				ImGui::Text("\tTotal frame time: %.1lfms", stats->frameTotal);
				ImGui::Text("\tTotal frame render time: %.1lfms", stats->renderTotal);

				ImGui::Text("\tGeneral");
				ImGui::Text("\t\tUpdate programs: %.3lfms", stats->frame.updatePrograms);
				ImGui::Text("\tRendering");
				ImGui::Text("\t\tzPrepass: %.3lfms", stats->frame.zPrepass);
				ImGui::Text("\t\tRender models: %.3lfms", stats->frame.renderModels);
				ImGui::Text("\t\tRender envmap: %.3lfms", stats->frame.background);
				ImGui::Text("\t\tResolve MSAA: %.3lfms", stats->frame.resolveMSAA);
				ImGui::Text("\tPost-Process");
				ImGui::Text("\t\tBloom total: %.3lfms", stats->frame.bloomTotal);
				ImGui::Text("\t\t\tBloom prefilter: %.3lfms", stats->frame.bloomPrefilter);
				ImGui::Text("\t\t\tBloom downsample: %.3lfms", stats->frame.bloomDownsample);
				ImGui::Text("\t\t\tBloom upsample first pass: %.3lfms", stats->frame.bloomUpsampleFirst);
				ImGui::Text("\t\t\tBloom upsample: %.3lfms", stats->frame.bloomUpsample);
				ImGui::Text("\t\tFinal compositing: %.3lfms", stats->frame.finalCompositing);

				ImGui::Text("\tImGui");
				ImGui::Text("\t\tGui description: %.1lfms", stats->imguiDesc);
				ImGui::Text("\t\tGui rendering: %.1lfms", stats->imguiRender);

				ImGui::Separator();

				auto renderableView = g_World.GetRegistry().view<Renderable>();

				ImGui::Text("Render stats");
				ImGui::Text("Drawing %d models", (i32)renderableView.size());
				i64 vertexTotal   = 0;
				i64 triangleTotal = 0;
				for (i32 i = 0; i < renderableView.size(); ++i)
				{
					auto entity     = renderableView[i];
					auto renderable = renderableView.get<Renderable>(entity);

					i64 vertexCount   = renderable.mesh->GetMesh().vertexCount;
					i64 triangleCount = renderable.mesh->GetMesh().indexCount / 3;
					ImGui::Text("\tModel %d has %lld vertices and %lld triangles", i, vertexCount, triangleCount);
					vertexTotal += vertexCount;
					triangleTotal += triangleCount;
				}
				ImGui::Text("Totalizing %lld vertices and %lld triangles", vertexTotal, triangleTotal);
			}
			ImGui::End();

			static bool show = true;
			ImGui::ShowDemoWindow(&show);
		}
		ImGui::End();

		textureDialog.Display();
		if (textureDialog.HasSelected())
		{
			std::string textureFile = textureDialog.GetSelected().string();
			*selectedTexture        = LoadTexture(textureFile.c_str());
			textureDialog.ClearSelected();
		}

		ImGui::Render();
		ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

		if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
		{
			GLFWwindow* backupCurrentContext = glfwGetCurrentContext();
			ImGui::UpdatePlatformWindows();
			ImGui::RenderPlatformWindowsDefault();
			glfwMakeContextCurrent(backupCurrentContext);
		}

		glfwSwapBuffers(window);
		glfwPollEvents();
	}

	glfwTerminate();

	return 0;
}

f64  lastX, lastY;
bool movingCamera = false;

inline bool inViewport(f64 x, f64 y)
{
	return (x >= g_ViewportX && x <= (g_ViewportX + g_ViewportW)) && (y >= g_ViewportY && y <= (g_ViewportY + g_ViewportH));
}

static void MouseButtonCallback(GLFWwindow* window, i32 button, i32 action, i32 mods)
{
	if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS)
	{
		f64 x, y;
		glfwGetCursorPos(window, &x, &y);

		if (inViewport(x, y))
		{
			movingCamera = true;
			lastX        = x;
			lastY        = y;
		}
	}
	else if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_RELEASE)
	{
		movingCamera = false;
	}
}

static void MouseMoveCallback(GLFWwindow* window, f64 x, f64 y)
{
	if (movingCamera)
	{
		const f64 dx = 0.1f * (x - lastX);
		const f64 dy = 0.1f * (y - lastY);

		g_Camera.phi += dx;
		g_Camera.theta = beard::clamp(g_Camera.theta + (f32)dy, 10.0f, 170.0f);

		lastX = x;
		lastY = y;
	}
}

static void KeyCallback(GLFWwindow* window, i32 key, i32 scancode, i32 action, i32 mods)
{
	if (key == GLFW_KEY_ESCAPE && action == GLFW_RELEASE)
	{
		glfwSetWindowShouldClose(window, GLFW_TRUE);
	}

	if (key == GLFW_KEY_F2 && action == GLFW_RELEASE)
	{
		static int swapInterval = 1;
		swapInterval ^= 1;

		glfwSwapInterval(swapInterval);
	}
}

static void WheelCallback(GLFWwindow* window, f64 x, f64 y)
{
	if (!movingCamera)
	{
		f64 mouseX, mouseY;
		glfwGetCursorPos(window, &mouseX, &mouseY);

		if (inViewport(mouseX, mouseY))
		{
			constexpr f32 minDistance = 0.01f;
			constexpr f32 maxDistance = 1000.0f;

			const f32 multiplier = 2.5f * (g_Camera.distance - minDistance) / (maxDistance - minDistance);

			const f32 distance = g_Camera.distance - (f32)y * multiplier;

			g_Camera.distance = beard::clamp(distance, minDistance, maxDistance);
		}
	}
}

static void FramebufferSizeCallback(GLFWwindow* window, i32 width, i32 height)
{
	g_Width  = width;
	g_Height = height;
}

void SetupUI(GLFWwindow* window)
{
	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO();
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
	io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
	io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;

	ImGui::StyleColorsDark();

	ImGuiStyle& style = ImGui::GetStyle();
	if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
	{
		style.WindowRounding              = 0.0f;
		style.Colors[ImGuiCol_WindowBg].w = 1.0f;
	}

	ImGui_ImplGlfw_InitForOpenGL(window, true);
	ImGui_ImplOpenGL3_Init("#version 450");
}

static void DropCallback(GLFWwindow* window, i32 count, const char** paths)
{
	for (i32 i = 0; i < count; ++i)
	{
		std::string ext = GetFileExtension(paths[i]);
		if (ext == "hdr")
		{
			LoadEnvironment(paths[i], g_Env);
		}
		else
		{
			auto view = g_World.GetRegistry().view<Renderable>();
			for (auto entity : view)
			{
				g_World.RemoveEntity(entity);
			}

			LoadScene(paths[i], &g_World);
		}
	}
}

void APIENTRY DebugOutput(GLenum source, GLenum type, u32 id, GLenum severity, GLsizei length, const char* message, const void* userParam)
{
	// ignore non-significant error/warning codes
	if (id == 131169 || id == 131185 || id == 131218 || id == 131204)
		return;

	fprintf(stderr, "---------------\n");
	fprintf(stderr, "Debug message (%d): %s\n", id, message);

	switch (source)
	{
		case GL_DEBUG_SOURCE_API:
			fprintf(stderr, "Source: API");
			break;
		case GL_DEBUG_SOURCE_WINDOW_SYSTEM:
			fprintf(stderr, "Source: Window System");
			break;
		case GL_DEBUG_SOURCE_SHADER_COMPILER:
			fprintf(stderr, "Source: Shader Compiler");
			break;
		case GL_DEBUG_SOURCE_THIRD_PARTY:
			fprintf(stderr, "Source: Third Party");
			break;
		case GL_DEBUG_SOURCE_APPLICATION:
			fprintf(stderr, "Source: Application");
			break;
		case GL_DEBUG_SOURCE_OTHER:
			fprintf(stderr, "Source: Other");
			break;
	}
	fprintf(stderr, "\n");

	switch (type)
	{
		case GL_DEBUG_TYPE_ERROR:
			fprintf(stderr, "Type: Error");
			break;
		case GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR:
			fprintf(stderr, "Type: Deprecated Behaviour");
			break;
		case GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR:
			fprintf(stderr, "Type: Undefined Behaviour");
			break;
		case GL_DEBUG_TYPE_PORTABILITY:
			fprintf(stderr, "Type: Portability");
			break;
		case GL_DEBUG_TYPE_PERFORMANCE:
			fprintf(stderr, "Type: Performance");
			break;
		case GL_DEBUG_TYPE_MARKER:
			fprintf(stderr, "Type: Marker");
			break;
		case GL_DEBUG_TYPE_PUSH_GROUP:
			fprintf(stderr, "Type: Push Group");
			break;
		case GL_DEBUG_TYPE_POP_GROUP:
			fprintf(stderr, "Type: Pop Group");
			break;
		case GL_DEBUG_TYPE_OTHER:
			fprintf(stderr, "Type: Other");
			break;
	}
	fprintf(stderr, "\n");

	switch (severity)
	{
		case GL_DEBUG_SEVERITY_HIGH:
			fprintf(stderr, "Severity: high");
			break;
		case GL_DEBUG_SEVERITY_MEDIUM:
			fprintf(stderr, "Severity: medium");
			break;
		case GL_DEBUG_SEVERITY_LOW:
			fprintf(stderr, "Severity: low");
			break;
		case GL_DEBUG_SEVERITY_NOTIFICATION:
			fprintf(stderr, "Severity: notification");
			break;
	}
	fprintf(stderr, "\n\n");
}
