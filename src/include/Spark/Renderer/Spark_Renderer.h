#pragma once

#include <Spark/Renderer/Spark_Environment.h>
#include <Spark/Renderer/Spark_Material.h>
#include <Spark/Renderer/Spark_Mesh.h>
#include <Spark/Renderer/Spark_Program.h>

#include <beard/core/macros.h>

#include <glad/glad.h>
#include <entt/fwd.hpp>
#include <glm/glm.hpp>

#include <beard/containers/array.h>

struct Renderable {
  std::shared_ptr<Material> material;
  std::shared_ptr<RenderMesh> mesh;
};

struct RenderContext {
  glm::vec3 eyePosition;
  glm::mat4 model, view, proj;

  glm::vec3 lightDirection;

  const Environment* env;
};

struct Model {
  Material* material;
  RenderMesh* mesh;

  glm::mat4 worldTransform;

  void Draw(RenderContext* context) const;
};

struct CameraComponent {
  glm::mat4 proj;
  glm::vec3 position;
  bool active = true;

  // Other params
};

enum class BackgroundType {
  None = 0,
  Cubemap = 1,
  Radiance = 2,
  Irradiance = 3,
};

enum class LightType {
  Point,
  Directional,
  Spot,
};

struct Light {
  LightType type;
  glm::vec3 position;
  glm::vec3 direction;
  glm::vec3 color;
  f32 innerAngle;
  f32 outerAngle;
};

class World;

class Renderer {
 public:
  NONCOPYABLE(Renderer);
  NONMOVEABLE(Renderer);

  static Renderer& Get();

  void Initialize(const glm::vec2& initSize);
  void Render(const World& world);

  void Resize(const glm::vec2& newSize);

 private:
  void ShadowPass(const World& world);
  void LightPass(const World& world);
  void ResolveMSAA();
  void Bloom();
  void Compose();

 public:
  BackgroundType backgroundType = BackgroundType::Cubemap;
  i32 backgroundMipLevel = 0;

  struct RenderConfig {
    bool wireframeEnabled = false;
    glm::vec3 wireframeColor = glm::vec3{0.0f, 0.0f, 0.0f};
    float wireframeIntensity = 1.0f;
  } config;

  struct BloomParams {
    bool enabled = true;
    f32 threshold = 1.0f;
    f32 knee = 0.1f;
    f32 upsampleScale = 1.0f;
    f32 intensity = 1.0f;
  } bloom;

  u32 shadowMapArray = 0;

  u32 msaaRenderTexture = 0;
  u32 resolveTexture = 0;
  u32 msaaDepthRenderBuffer = 0;

  // Post-process textures
  u32 bloomTextures[3] = {};

  // Final render texture
  u32 outputTexture = 0;

  Environment env;

 private:
  Renderer() = default;
  ~Renderer() = default;

  glm::vec2 m_framebufferSize = glm::vec2{0.0f, 0.0f};

  glm::vec2 m_bloomSize = glm::vec2{0.0f, 0.0f};
  i32 m_bloomPasses = 0;
  i32 m_bloomComputeWorkGroupSize = 4;

  u32 m_fbos[2] = {};

  u32 m_matricesUBO = 0;
  u32 m_lightsSSBO = 0;

#define m_msaaFB m_fbos[0]
#define m_resolveFB m_fbos[1]

  Program* m_backgroundProgram = nullptr;

  // Post-process compute shaders
  Program* m_bloomProgram = nullptr;
  Program* m_outputProgram = nullptr;

  Material* m_WireframeMaterial = nullptr;
};
