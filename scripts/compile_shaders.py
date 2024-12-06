import os
import shutil
from pathlib import Path


cwd = os.path.dirname(__file__)
os.chdir(cwd)

shaders_path = '../assets/shaders'
output_path = f'{shaders_path}/compiled'

VULKAN_SDK = os.getenv("VULKAN_SDK")

glslc = f'{VULKAN_SDK}/Bin/glslc'
print('glsl compiler path: ' + glslc)

def clear_old_builds():
	if not os.path.exists(output_path): return
	shutil.rmtree(output_path)

def make_path_for_file(path):
	directory = os.path.dirname(path)
	Path(directory).mkdir(parents=True, exist_ok=True)


def compile_shader(input, output):
	input = os.path.normpath(input)
	output = os.path.normpath(output)

	make_path_for_file(output)

	command = f'{glslc} {input} -o {output}'
	print(command)
	os.system(command)

print('clearing old spv files from ' + output_path + '...')
clear_old_builds()

for root, dirs, files in os.walk(shaders_path):
	for file in files:
		if file.endswith('.vert') or file.endswith('.frag'):
			local_root = root.removeprefix(shaders_path)
			compile_shader(f'{root}/{file}', f'{output_path}{local_root}/{file}.spv')
