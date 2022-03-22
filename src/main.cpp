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

#include <Spark/UI/Spark_UI.h>

#include <beard/containers/array.h>
#include <beard/containers/hash_map.h>
#include <beard/math/math.h>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtc/matrix_transform.hpp>

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

	UI::Setup(window);

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

			g_World.Update();

		UI::UpdateAndRender(&g_World);

		glfwSwapBuffers(window);
		glfwPollEvents();
	}

	glfwTerminate();

	return 0;
}

f64  lastX, lastY;
bool movingCamera = false;

static void MouseButtonCallback(GLFWwindow* window, i32 button, i32 action, i32 mods)
{
	if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS)
	{
		f64 x, y;
		glfwGetCursorPos(window, &x, &y);

		if (UI::IsCursorInViewport(x, y))
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

		if (UI::IsCursorInViewport(mouseX, mouseY))
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

	UI::Resize(width, height);
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
			UI::ClearSelection();
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
