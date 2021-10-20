#pragma once

#include <Beard/Macros.h>
#include <Beard/Array.h>

#include <glm/glm.hpp>

enum class IndexType
{
	Unsigned16,
	Unsigned32,
};

// NOTE: This is not the most efficient way to render a mesh,
// but this is the easiest to update and maintain for now.
struct Mesh
{
	Beard::Array<glm::vec3> positions;
	Beard::Array<glm::vec3> normals;
	Beard::Array<glm::vec2> texcoords;
	Beard::Array<glm::vec4> weights;
	Beard::Array<glm::vec4> bones;

	Beard::Array<u8> indices;

	IndexType indexType;
	u32       indexCount;
	u32       vertexCount;
};

class RenderMesh
{
public:
	explicit RenderMesh(Mesh mesh);

	void Draw() const;
	void DrawInstanced(u32 instanceCount) const;

	// clang-format off
	glm::vec3* GetPositionBuffer() const { return m_PositionBuffer; }
	glm::vec3* GetNormalBuffer() const   { return m_NormalBuffer; }
	const Mesh& GetMesh() const          { return m_Mesh; }
	// clang-format on

private:
	Mesh m_Mesh;

	glm::vec3* m_PositionBuffer;
	glm::vec3* m_NormalBuffer;

	u32 m_VAO         = 0;
	u32 m_Buffer      = 0;
	u32 m_IndexStride = 0;
	u32 m_IndexType   = 0;
};
