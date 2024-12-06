#version 450

layout(location = 1) in vec3 iworldPosition;
layout(location = 2) in vec3 iworldNormal;
layout(location = 0) in vec3 icolor;

layout (location = 0) out vec4 ocolor;

struct PointLight {
	vec4 position; // ignore w
	vec4 color; // w is intensity
};
layout(set = 0, binding = 0) uniform GlobalUbo {
	mat4 projection;
	mat4 view;
	vec4 ambientLightColor;
	// PointLight pointLights[10 /* replace const with specialization constants */];
	// int numLights;
} ubo;

layout(push_constant) uniform Push {
	mat4 modelMatrix;
	mat4 normalMatrix;
} push;

void main() {
	// vec3 diffuseLight = ubo.ambientLightColor.xyz * ubo.ambientLightColor.w;
	// vec3 surfaceNormal = normalize(iworldNormal);

	// for (int i = 0; i < ubo.numLights; ++i) {
	// 	PointLight light = ubo.pointLights[i];
	// 	vec3 lightDirection = light.position.xyz - iworldPosition;
	// 	float attenuation = 1.0f / dot(lightDirection, lightDirection);
	// 	float cosAngIncidence = max(dot(surfaceNormal, normalize(lightDirection)), 0);
	// 	vec3 intensity = light.color.xyz * light.color.w * attenuation;
  //
	// 	diffuseLight += intensity * cosAngIncidence;
	// }




	ocolor = vec4(1, 1, 1, 1);
	// ocolor = vec4(diffuseLight * icolor, 1.0);
}
