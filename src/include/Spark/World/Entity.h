#pragma once

#include <Spark/World/World.h>

#include <Beard/Macros.h>

#include <entt/entt.hpp>

#include <glm/glm.hpp>

class Entity
{
	friend class World;

public:
	DEFAULT_CTORS(Entity);

	Entity() = default;
	Entity(entt::entity entity, entt::registry* world)
	    : m_Entity{entity}
	    , m_World{world}
	{
	}

	~Entity() = default;

	template <typename T, typename... Args>
	T& AddComponent(Args&&... args)
	{
		return m_World->emplace_or_replace<T>(m_Entity, std::forward<Args>(args)...);
	}

	template <typename T>
	T& GetComponent() const
	{
		return m_World->get<T>(m_Entity);
	}

	const glm::mat4& GetTransform() const;
	glm::mat4&       GetTransform();
	void             SetTransform(const glm::mat4& transform);
	void             SetTransform(glm::mat4&& transform);

private:
	entt::entity    m_Entity{entt::null};
	entt::registry* m_World{nullptr};
};