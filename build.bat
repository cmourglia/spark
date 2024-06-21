@echo off

for %%f in (shaders/*.glsl) do (
    glslangValidator -V shaders/%%f -o shaders/bin/%%~nf.spv
)

odin run spark -o:none -debug

