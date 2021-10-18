#include <Spark/World/World.h>

#include <Spark/World/Entity.h>

#include <Spark/Renderer/Renderer.h>

void World::Update()
{
	Renderer::Get().Render(*this);
}

Entity World::CreateEntity()
{
	auto entity = m_Registry.create();
	m_Registry.emplace<TransformComponent>(entity);

	return {entity, &m_Registry};
}

void World::RemoveEntity(Entity entity)
{
	m_Registry.destroy(entity.m_Entity);
}

void World::RemoveEntity(entt::entity entity)
{
	m_Registry.destroy(entity);
}

Entity World::GetActiveCamera() const
{
	auto cameras = m_Registry.view<CameraComponent>();
	for (auto [entity, camera] : cameras.each())
	{
		if (camera.active)
		{
			return {entity, (entt::registry*)&m_Registry};
		}
	}

	return Entity{};
}