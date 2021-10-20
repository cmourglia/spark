#include <Spark/Renderer/Spark_Mesh.h>

#include <glad/glad.h>

template <typename T>
void BindBuffer(const Beard::Array<T>& buffer, i32 vao, i32 vbo, i32 bindingPoint, i32 offset, i32 size, GLenum dataType)
{
	if (!buffer.IsEmpty())
	{
		glNamedBufferSubData(vbo, offset, buffer.DataSize(), buffer.Data());
		glEnableVertexArrayAttrib(vao, bindingPoint);
		glVertexArrayAttribBinding(vao, bindingPoint, bindingPoint);
		glVertexArrayVertexBuffer(vao, bindingPoint, vbo, offset, sizeof(T));
		glVertexArrayAttribFormat(vao, bindingPoint, size, dataType, GL_FALSE, 0);
	}
}

RenderMesh::RenderMesh(Mesh mesh)
    : m_Mesh(std::move(mesh))
{
	i32 indexOffset    = 0;
	i32 indexSize      = m_Mesh.indices.DataSize();
	i32 positionOffset = indexOffset + indexSize;
	i32 positionSize   = m_Mesh.positions.DataSize();
	i32 normalOffset   = positionOffset + positionSize;
	i32 normalSize     = m_Mesh.normals.DataSize();
	i32 texcoordOffset = normalOffset + normalSize;
	i32 texcoordSize   = m_Mesh.texcoords.DataSize();
	i32 weightsOffset  = texcoordOffset + texcoordSize;
	i32 weightsSize    = m_Mesh.weights.DataSize();
	i32 bonesOffset    = weightsOffset + weightsSize;
	i32 bonesSize      = m_Mesh.bones.DataSize();

	i32 bufferSize = 0;
	bufferSize += indexSize;
	bufferSize += positionSize;
	bufferSize += normalSize;
	bufferSize += texcoordSize;
	bufferSize += weightsSize;
	bufferSize += bonesSize;

	m_IndexStride = mesh.indexType == IndexType::Unsigned16 ? 2 : 4;
	m_IndexType   = mesh.indexType == IndexType::Unsigned16 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT;

	glCreateVertexArrays(1, &m_VAO);
	glCreateBuffers(1, &m_Buffer);

	// u32 accessFlags = GL_MAP_WRITE_BIT | GL_MAP_READ_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT;
	u32 accessFlags = 0;
	glNamedBufferStorage(m_Buffer, bufferSize, nullptr, accessFlags | GL_DYNAMIC_STORAGE_BIT);

	glVertexArrayElementBuffer(m_VAO, m_Buffer);
	glNamedBufferSubData(m_Buffer, indexOffset, indexSize, m_Mesh.indices.Data());

	// Upload data
	BindBuffer(m_Mesh.positions, m_VAO, m_Buffer, 0, positionOffset, 3, GL_FLOAT);
	BindBuffer(m_Mesh.normals, m_VAO, m_Buffer, 1, normalOffset, 3, GL_FLOAT);
	BindBuffer(m_Mesh.texcoords, m_VAO, m_Buffer, 2, texcoordOffset, 2, GL_FLOAT);
	BindBuffer(m_Mesh.weights, m_VAO, m_Buffer, 3, weightsOffset, 4, GL_FLOAT);
	BindBuffer(m_Mesh.bones, m_VAO, m_Buffer, 4, bonesOffset, 4, GL_FLOAT);

	// Get positions and normal buffer
	// glm::vec3* buffer = (glm::vec3*)glMapNamedBufferRange(m_Buffer, positionOffset, positionSize + normalSize, accessFlags);
	// m_PositionBuffer  = buffer;
	// m_NormalBuffer    = buffer + positionSize;
}

void RenderMesh::Draw() const
{
	glBindVertexArray(m_VAO);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_Buffer);
	glDrawElements(GL_TRIANGLES, m_Mesh.indexCount, m_IndexType, nullptr);
}

void RenderMesh::DrawInstanced(u32 instanceCount) const
{
	glBindVertexArray(m_VAO);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_Buffer);
	glDrawElementsInstanced(GL_TRIANGLES, m_Mesh.indexCount, m_IndexType, nullptr, instanceCount);
}
