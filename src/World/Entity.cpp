#include <Spark/World/Entity.h>

const glm::mat4& Entity::GetTransform() const
{
	return GetComponent<TransformComponent>().transform;
}

glm::mat4& Entity::GetTransform()
{
	return GetComponent<TransformComponent>().transform;
}

void Entity::SetTransform(const glm::mat4& transform)
{
	GetComponent<TransformComponent>().transform = transform;
}

void Entity::SetTransform(glm::mat4&& transform)
{
	GetComponent<TransformComponent>().transform = std::move(transform);
}
