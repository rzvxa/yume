#version 450

#define FORWARD_LIGHT_COUNT 4

layout(location = 0) in vec3 in_world_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_tangent;
layout(location = 3) in vec4 in_color;
layout(location = 4) in vec2 in_uv;

layout(location = 0) out vec4 frag_color;

layout(set = 0, binding = 1) uniform UniformBufferObject {
	vec4 lights[FORWARD_LIGHT_COUNT];
	vec4 ambient_color;
	float exposure;
	float gamma;
} scene_data;

void main() {
	frag_color = in_color * scene_data.ambient_color;
}

