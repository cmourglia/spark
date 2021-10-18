#include <Spark/Renderer/Texture.h>

#include <Spark/Core/Utils.h>

#include <Beard/HashMap.h>
#include <Beard/Math.h>

#include <stb_image.h>
#include <glad/glad.h>

static Beard::StringHashMap<u32> g_textures;

u32 LoadTexture(const std::string& filename)
{
	if (auto it = g_textures.Find(filename); it != g_textures.end())
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

	GLuint texture;
	glCreateTextures(GL_TEXTURE_2D, 1, &texture);

	const i32 levels = log2f(Beard::Min(w, h));

	GLenum format, internalFormat;
	switch (c)
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

	glTextureStorage2D(texture, levels, internalFormat, w, h);
	glTextureSubImage2D(texture, 0, 0, 0, w, h, format, GL_UNSIGNED_BYTE, data);
	glGenerateTextureMipmap(texture);

	stbi_image_free(data);

	g_textures.Add(filename, texture);

	return texture;
}
