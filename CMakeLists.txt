cmake_minimum_required(VERSION 3.15)
project(spark)

set(CMAKE_CXX_STANDARD 20)

add_subdirectory(external)

set(CORE_SRC )

set(CORE_INC
    src/include/Spark/Core/Utils.h)

set(RENDERER_SRC
    src/Renderer/Environment.cpp
    src/Renderer/FrameStats.cpp
    src/Renderer/GenDFG.cpp
    src/Renderer/Material.cpp
    src/Renderer/Program.cpp
    src/Renderer/Renderer.cpp
    src/Renderer/RenderPrimitives.cpp
    src/Renderer/Texture.cpp
)

set(RENDERER_INC
    src/include/Spark/Renderer/Environment.h
    src/include/Spark/Renderer/FrameStats.h
    src/include/Spark/Renderer/Material.h
    src/include/Spark/Renderer/Program.h
    src/include/Spark/Renderer/Renderer.h
    src/include/Spark/Renderer/RenderPrimitives.h
    src/include/Spark/Renderer/Texture.h
)

set(ASSETS_SRC
    src/Assets/Asset.cpp
    src/Assets/LoadAssimpAsset.cpp
    src/Assets/LoadGLTFAsset.cpp
)

set(ASSETS_INC
    src/include/Spark/Assets/Asset.h
)

set(WORLD_SRC
    src/World/World.cpp
    src/World/Entity.cpp
)

set(WORLD_INC
    src/include/Spark/World/World.h
    src/include/Spark/World/Entity.h
)

add_executable(${PROJECT_NAME}
    src/main.cpp

    ${CORE_SRC}
    ${CORE_INC}
    ${RENDERER_SRC}
    ${RENDERER_INC}
    ${ASSETS_SRC}
    ${ASSETS_INC}
    ${WORLD_SRC}
    ${WORLD_INC}
)

target_link_libraries(${PROJECT_NAME} PRIVATE glm glfw glad stb_image imgui assimp EnTT BeardLibrary tinygltf)
target_include_directories(${PROJECT_NAME} PRIVATE src/include)
target_compile_definitions(${PROJECT_NAME} PRIVATE $<$<CONFIG:Debug>:_DEBUG=1> NOMINMAX _CRT_SECURE_NO_WARNINGS)

target_compile_options(${PROJECT_NAME} PRIVATE $<$<CXX_COMPILER_ID:Clang>:-W3 -Werror>)