#!/usr/bin/python

import os
import subprocess
import sys

content = os.listdir("shaders")

def run_cmd(cmd):
    #process = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    process = subprocess.run(cmd, stdout=None, stderr=None)
    #output, error = process.communicate()

    # Check if the command was executed without errors
    #if error is None:
    #    # Filter lines with 'python3'
    #    python_processes = [line for line in output.decode('utf-8').split('\n')]

    #    # Write the output to a file
    #    for p in python_processes:
    #        if len(p) > 0:
    #            print(p)
    #else:
    #    print(f"Error occurred while executing command: {error}")


for entry in content:
    if "." not in entry:
        continue

    items = entry.split(".")

    if len(items) != 3:
        continue

    shader_name = os.path.join("shaders", "bin", ".".join(items[0:2]) + ".spv")

    cmd = ["glslangValidator", "-V", os.path.join("shaders", entry), "-o", shader_name]
    run_cmd(cmd)

cmd = ["odin", "run", "spark"]

if len(sys.argv) > 1 and sys.argv[1] == "release":
    cmd += ["-o:speed"]
else:
    cmd += ["-o:none", "-debug"]
run_cmd(cmd)


