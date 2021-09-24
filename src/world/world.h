#pragma once

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

#include <entt/entt.hpp>

struct Name
{
	std::string name;
};

struct Position
{
	glm::vec3 position;
	glm::quat orientation;
};

struct Velocity
{
	glm::vec3 linearVelocity;
	glm::quat angularVelocity;
};

struct Transform
{
	glm::mat4 transform;
};

struct World
{
	entt::registry world;
};