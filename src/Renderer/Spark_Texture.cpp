#include <Spark/Renderer/Spark_Texture.h>

#include <Spark/Core/Spark_Utils.h>

#include <beard/containers/hash_map.h>
#include <beard/math/math.h>

#include <stb_image.h>
#include <glad/glad.h>

static beard::string_hash_map<u32> g_Textures;

u32 LoadTexture(const std::string& filename)
{
	if (auto it = g_Textures.find(filename); it != g_Textures.end())
	{
		return it->second;
	}

	stbi_set_flip_vertically_on_load(true);

	i32      w, h, c;
	uint8_t* data = stbi_load(filename.c_str(), &w, &h, &c, 0);

	stbi_set_flip_vertically_on_load(false);

	if (data == nullptr)
	{
		return 0;
	}

	return LoadTexture(w, h, c, data);
}

u32 LoadTexture(i32 width, i32 height, i32 components, const u8* data)
{
	GLuint texture;
	glCreateTextures(GL_TEXTURE_2D, 1, &texture);

	const i32 levels = log2f(beard::min(width, height));

	GLenum format, internalFormat;
	switch (components)
	{
		case 1:
			format         = GL_R;
			internalFormat = GL_R8;
			break;

		case 2:
			format         = GL_RG;
			internalFormat = GL_RG8;
			break;

		case 3:
			format         = GL_RGB;
			internalFormat = GL_RGB8;
			break;

		case 4:
			format         = GL_RGBA;
			internalFormat = GL_RGBA8;
			break;
	}

	glTextureStorage2D(texture, levels, internalFormat, width, height);
	glTextureSubImage2D(texture, 0, 0, 0, width, height, format, GL_UNSIGNED_BYTE, data);
	glGenerateTextureMipmap(texture);

	return texture;
}