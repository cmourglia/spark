#pragma once

#include <beard/core/macros.h>

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

#include <entt/entt.hpp>

struct NameComponent {
  std::string name;
};

struct PositionComponent {
  glm::vec3 position;
  glm::quat orientation;
};

struct VelocityComponent {
  glm::vec3 linearVelocity;
  glm::quat angularVelocity;
};

struct TransformComponent {
  glm::mat4 transform;
};

class Entity;

class World {
 public:
  void Update();

  Entity CreateEntity();
  void RemoveEntity(Entity);
  void RemoveEntity(entt::entity);

  Entity GetActiveCamera() const;
  Entity GetEntity(entt::entity entity) const;

  entt::registry& GetRegistry() { return m_Registry; }
  const entt::registry& GetRegistry() const { return m_Registry; }

 private:
  entt::registry m_Registry;
};