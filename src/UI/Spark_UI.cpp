#include <Spark/UI/Spark_UI.h>

// #include "imfilebrowser.h

#include <Spark/World/Spark_World.h>
#include <Spark/World/Spark_Entity.h>

#include <Spark/Renderer/Spark_FrameStats.h>
#include <Spark/Renderer/Spark_Renderer.h>

#include <beard/math/math.h>

#include <imgui.h>
#include <imgui_internal.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <GLFW/glfw3.h>

namespace UI
{
global_variable f32 g_Width                    = 0.0f;
global_variable f32 g_Height                   = 0.0f;
global_variable f32 g_ViewportX                = 0.0f;
global_variable f32 g_ViewportY                = 0.0f;
global_variable f32 g_ViewportW                = 0.0f;
global_variable f32 g_ViewportH                = 0.0f;
global_variable glm::vec2   g_LastViewportSize = {0.0f, 0.0f};
global_variable GLFWwindow* g_Window           = nullptr;
global_variable entt::entity g_SelectedEntity  = entt::null;

void Setup(GLFWwindow* window)
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

	g_Window = window;
}

void Resize(u32 width, u32 height)
{
	g_Width  = (f32)width;
	g_Height = (f32)height;
}

void UpdateAndRender(World* world)
{
	Renderer& renderer = Renderer::Get();
	ImGuiIO&  io       = ImGui::GetIO();

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
		ImGui::DockBuilderSetNodeSize(dockspace_id, ImVec2(g_Width, g_Height));

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
			glfwGetWindowPos(g_Window, &wx, &wy);

			vMin.x -= (f32)wx;
			vMin.y -= (f32)wy;
			vMax.x -= (f32)wx;
			vMax.y -= (f32)wy;

			g_ViewportX = vMin.x;
			g_ViewportY = vMin.y;
			g_ViewportW = vMax.x - vMin.x;
			g_ViewportH = vMax.y - vMin.y;

			glm::vec2 size(g_ViewportW, g_ViewportH);

			if (size != g_LastViewportSize)
			{
				auto  cameraEntity    = world->GetActiveCamera();
				auto& cameraComponent = cameraEntity.GetComponent<CameraComponent>();
				cameraComponent.proj  = glm::perspective(60.0f * beard::math::DegToRad, (f32)size.x / size.y, 0.1f, 5000.0f);

				renderer.Resize(size);
				g_LastViewportSize = size;
			}

			ImTextureID id;
			id = (void*)(intptr_t)renderer.outputTexture;
			ImGui::Image(id, ImVec2(size.x, size.y), ImVec2(0, 1), ImVec2(1, 0));
		}
		ImGui::End();

		ImGui::Begin("Entities");
		{
			const auto& view = world->GetRegistry().view<NameComponent>();

			for (auto entity : view)
			{
				if (ImGui::Selectable(view.get<NameComponent>(entity).name.c_str(), g_SelectedEntity == entity))
				{
					g_SelectedEntity = entity;
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

		ImGui::Begin("Renderer");
		{
			ImGui::Begin("Config");
			{
				ImGui::Checkbox("Draw wireframe", &renderer.config.wireframeEnabled);
				ImGui::ColorEdit3("Wireframe color", &renderer.config.wireframeColor.r);
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
		}
		ImGui::End();

		ImGui::Begin("Properties");
		if (ImGui::CollapsingHeader("Material", ImGuiTreeNodeFlags_DefaultOpen))
		{
			if (g_SelectedEntity != entt::null)
			{
				auto      entity     = world->GetEntity(g_SelectedEntity);
				auto&     renderable = entity.GetComponent<Renderable>();
				Material* material   = renderable.material.get();

				ImGui::ColorEdit3("Albedo", &material->albedo.x);

				ImGui::Checkbox("Albedo texture", &material->hasAlbedoTexture);
				if (material->hasAlbedoTexture)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->albedoTexture, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->albedoTexture;
						// textureDialog.Open();
					}
				}

				ImGui::SliderFloat("Roughness", &material->roughness, 0.0f, 1.0f);

				ImGui::Checkbox("Roughness texture", &material->hasRoughnessTexture);
				if (material->hasRoughnessTexture)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->roughnessTexture, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->roughnessTexture;
						// textureDialog.Open();
					}
				}

				ImGui::SliderFloat("Metallic", &material->metallic, 0.0f, 1.0f);

				ImGui::Checkbox("Metallic texture", &material->hasMetallicTexture);
				if (material->hasMetallicTexture)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->metallicTexture, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->metallicTexture;
						// textureDialog.Open();
					}
				}

				ImGui::Checkbox("Metallic - Roughness texture", &material->hasMetallicRoughnessTexture);
				if (material->hasMetallicRoughnessTexture)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->metallicRoughnessTexture, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->metallicRoughnessTexture;
						// textureDialog.Open();
					}
				}

				ImGui::Checkbox("Emissive", &material->hasEmissive);
				if (material->hasEmissive)
				{
					ImGui::ColorEdit3("Emissive", &material->emissive.x);
				}

				ImGui::Checkbox("Emissive texture", &material->hasEmissiveTexture);
				if (material->hasEmissiveTexture)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->emissiveTexture, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->emissiveTexture;
						// textureDialog.Open();
					}
				}

				if (material->hasEmissive || material->hasEmissiveTexture)
				{
					ImGui::SliderFloat("Emissive factor", &material->emissiveFactor, 0.0f, 10.0f);
				}

				ImGui::Checkbox("Normal map", &material->hasNormalMap);
				if (material->hasNormalMap)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->normalMap, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->normalMap;
						// textureDialog.Open();
					}
				}

				ImGui::Checkbox("AO map", &material->hasAmbientOcclusionMap);
				if (material->hasAmbientOcclusionMap)
				{
					if (ImGui::ImageButton((void*)(intptr_t)material->ambientOcclusionMap, ImVec2(64, 64), ImVec2(0, 1), ImVec2(1, 0)))
					{
						selectedTexture = &material->ambientOcclusionMap;
						// textureDialog.Open();
					}
				}
			}
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

			auto renderableView = world->GetRegistry().view<Renderable>();

			ImGui::Text("Render stats");
			ImGui::Text("Drawing %d models", (i32)renderableView.size());
			i64 vertexTotal   = 0;
			i64 triangleTotal = 0;
			for (i32 i = 0; i < renderableView.size(); ++i)
			{
				auto        entity = renderableView[i];
				const auto& mesh   = world->GetEntity(entity).GetComponent<MeshComponent>();

				i64 vertexCount   = mesh.vertexCount;
				i64 triangleCount = mesh.indexCount / 3;
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

	// textureDialog.Display();
	// if (textureDialog.HasSelected())
	// {
	// 	std::string textureFile = textureDialog.GetSelected().string();
	// 	*selectedTexture        = LoadTexture(textureFile.c_str());
	// 	textureDialog.ClearSelected();
	// }

	ImGui::Render();
	ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

	if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
	{
		GLFWwindow* backupCurrentContext = glfwGetCurrentContext();
		ImGui::UpdatePlatformWindows();
		ImGui::RenderPlatformWindowsDefault();
		glfwMakeContextCurrent(backupCurrentContext);
	}
}

void ClearSelection()
{
	g_SelectedEntity = entt::null;
}

bool IsCursorInViewport(f64 x, f64 y)
{
	return (x >= g_ViewportX && x <= (g_ViewportX + g_ViewportW)) && (y >= g_ViewportY && y <= (g_ViewportY + g_ViewportH));
}
}
