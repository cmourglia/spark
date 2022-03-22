cmake_minimum_required(VERSION 3.15)
project(spark)

set(CMAKE_CXX_STANDARD 20)

add_subdirectory(external)

set(CORE_SRC )

set(CORE_INC
    src/include/Spark/Core/Spark_Utils.h
    src/include/Spark/Core/Spark_Property.h
)

set(RENDERER_SRC
    src/Renderer/Spark_Environment.cpp
    src/Renderer/Spark_FrameStats.cpp
    src/Renderer/Spark_GenDFG.cpp
    src/Renderer/Spark_Material.cpp
    src/Renderer/Spark_Mesh.cpp
    src/Renderer/Spark_Program.cpp
    src/Renderer/Spark_Renderer.cpp
    src/Renderer/Spark_RenderPrimitives.cpp
    src/Renderer/Spark_Texture.cpp
)

set(RENDERER_INC
    src/include/Spark/Renderer/Spark_Environment.h
    src/include/Spark/Renderer/Spark_FrameStats.h
    src/include/Spark/Renderer/Spark_Material.h
    src/include/Spark/Renderer/Spark_Mesh.h
    src/include/Spark/Renderer/Spark_Program.h
    src/include/Spark/Renderer/Spark_Renderer.h
    src/include/Spark/Renderer/Spark_RenderPrimitives.h
    src/include/Spark/Renderer/Spark_Texture.h
)

set(ASSETS_SRC
    src/Assets/Spark_Asset.cpp
    src/Assets/Spark_LoadAssimpAsset.cpp
    src/Assets/Spark_LoadGLTFAsset.cpp
)

set(ASSETS_INC
    src/include/Spark/Assets/Spark_Asset.h
)

set(WORLD_SRC
    src/World/Spark_World.cpp
    src/World/Spark_Entity.cpp
    src/World/Spark_AnimationSystem.cpp
)

set(WORLD_INC
    src/include/Spark/World/Spark_World.h
    src/include/Spark/World/Spark_Entity.h
    src/include/Spark/World/Spark_AnimationSystem.h
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

target_link_libraries(${PROJECT_NAME} PRIVATE glm glfw glad stb_image imgui assimp EnTT beard tinygltf)
target_include_directories(${PROJECT_NAME} PRIVATE src/include)
target_compile_definitions(${PROJECT_NAME} PRIVATE $<$<CONFIG:Debug>:_DEBUG=1> NOMINMAX _CRT_SECURE_NO_WARNINGS)

target_compile_options(${PROJECT_NAME} PRIVATE $<$<CXX_COMPILER_ID:Clang>:-W3 -Werror>)