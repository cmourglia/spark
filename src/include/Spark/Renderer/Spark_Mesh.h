#pragma once

#include <beard/core/macros.h>
#include <beard/containers/array.h>

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
	beard::array<glm::vec3> positions;
	beard::array<glm::vec3> normals;
	beard::array<glm::vec2> texcoords;
	beard::array<glm::vec4> weights;
	beard::array<glm::vec4> bones;

	beard::array<u8> indices;

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
