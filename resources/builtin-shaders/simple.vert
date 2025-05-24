#version 460

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_tangent;
layout(location = 3) in vec4 in_color;
layout(location = 4) in vec2 in_uv;

layout(location = 0) out vec3 out_world_pos;
layout(location = 1) out vec3 out_normal;
layout(location = 2) out vec4 out_tangent;
layout(location = 3) out vec4 out_color;
layout(location = 4) out vec2 out_uv;

layout(set = 0, binding = 0) uniform UniformBufferObject {
	mat4 view_proj;
	vec3 cam_pos;
} camera_data;

struct ObjectData {
	mat4 model;
};

layout(std140, set = 1, binding = 0) readonly buffer ObjectBuffer {
	ObjectData objects[];
} object_buffer;

void main() {
	mat4 model = object_buffer.objects[gl_BaseInstance].model;
	vec4 world_pos = model * vec4(in_position, 1.0f);

	out_world_pos = world_pos.xyz;
	out_normal = mat3(model) * in_normal;
	out_tangent = vec4(mat3(model) * in_tangent.xyz, in_tangent.w);
	out_color = in_color;
	out_uv = in_uv;

	gl_Position = camera_data.view_proj * world_pos;
}

