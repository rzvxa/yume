#version 450

#define FORWARD_LIGHT_COUNT 4

layout(location = 0) in vec3 in_world_pos;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec4 in_tangent;
layout(location = 3) in vec4 in_color;
layout(location = 4) in vec2 in_uv;

layout(set = 0, binding = 0) uniform UniformBufferCameraObject {
	mat4 view_proj;
	vec3 cam_pos;
} camera_data;

struct LightData {
	vec3  pos;
  float range; // unused in directional lighting
  vec3  color;
  float intensity;
};

layout(set = 0, binding = 1) uniform UniformBufferSceneObject {
	LightData point_lights[FORWARD_LIGHT_COUNT];
  LightData directional_light;
	vec4      ambient_color;
	float     exposure;
	float     gamma;
} scene_data;

layout (set = 2, binding = 0) uniform sampler2D albedo_map;
layout (set = 2, binding = 1) uniform sampler2D normal_map;
layout (set = 2, binding = 2) uniform sampler2D ao_map;
layout (set = 2, binding = 3) uniform sampler2D metallic_map;
layout (set = 2, binding = 4) uniform sampler2D roughness_map;


layout (location = 0) out vec4 frag_color;

#define PI 3.1415926535897932384626433832795

// GGX Normal Distribution Function.
float D_GGX(float dotNH, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denom = dotNH * dotNH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (PI * denom * denom);
}

// Schlick–Smith Geometry Function.
float G_SchlickSmith(float dotNL, float dotNV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    float GL = dotNL / (dotNL * (1.0 - k) + k);
    float GV = dotNV / (dotNV * (1.0 - k) + k);
    return GL * GV;
}

// Fresnel function with Schlick’s approximation.
vec3 F_Schlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Calculate the Cook–Torrance specular contribution.
vec3 calculateSpecularBRDF(vec3 L, vec3 V, vec3 N, vec3 F0, float roughness) {
    vec3 H = normalize(V + L);
    float dotNH = max(dot(N, H), 0.0);
    float dotNL = max(dot(N, L), 0.0);
    float dotNV = max(dot(N, V), 0.0);
    float dotVH = max(dot(V, H), 0.0);

    float D = D_GGX(dotNH, roughness);
    float G = G_SchlickSmith(dotNL, dotNV, roughness);
    vec3 F = F_Schlick(dotVH, F0);

    float denom = max(4.0 * dotNL * dotNV, 0.001);
    return (D * G * F) / denom;
}

// -----------------------------------------------------------------------------
// Lambertian diffuse term.
vec3 diffuseLambert(vec3 albedo, vec3 N, vec3 L) {
    float dotNL = max(dot(N, L), 0.0);
    return (albedo / PI) * dotNL;
}

vec3 radiance(
            vec3  L,
            vec3  N,
            vec3  V,
            vec3  F0,

            vec3  light_color,
            float light_intensity,

            vec3  albedo,

            float roughness,
            float metallic
        ) {
        // Evaluate both specular and diffuse lighting.
        vec3 specular = calculateSpecularBRDF(L, V, N, F0, roughness);
        vec3 diffuse  = diffuseLambert(albedo, N, L) * (1.0 - metallic);

        // Dot factor for the current light.
        float NdotL = max(dot(N, L), 0.0);
        return (diffuse + specular) * light_color * light_intensity * NdotL;
}

void main() {
    // Sample material parameters.
    vec3 albedo    = texture(albedo_map, in_uv).rgb;
    float metallic = texture(metallic_map, in_uv).r;
    float roughness = texture(roughness_map, in_uv).r;

    // Use the vertex normal directly.
    vec3 N = normalize(in_normal);

    // Compute the view vector (from fragment to camera).
    vec3 V = normalize(camera_data.cam_pos - in_world_pos);

    // Calculate reflectance at normal incidence.
    // Dielectrics tend to have F0 ~ 0.04; metals use the albedo.
    vec3 F0 = mix(vec3(0.04), albedo, metallic);

    // Accumulate light contributions.
    vec3 Lo = vec3(0.0);

    {
        LightData light = scene_data.directional_light;
        vec3 L = normalize(-light.pos);
        Lo += radiance(L, N, V, F0, light.color, light.intensity, albedo, roughness, metallic);
    }

    for (int i = 0; i < FORWARD_LIGHT_COUNT; ++i) {
        LightData light = scene_data.point_lights[i];
        vec3 L = normalize(light.pos - in_world_pos);
        float distance = length(light.pos - in_world_pos);
        float attenuation = clamp(1.0 - (distance / light.range), 0.0, 1.0);
        attenuation = attenuation * attenuation;
        Lo += radiance(L, N, V, F0, light.color, light.intensity, albedo, roughness, metallic) * attenuation;
    }

   // Add ambient light (without AO).
    vec3 ambient = scene_data.ambient_color.rgb * scene_data.ambient_color.a * albedo;
    vec3 color = ambient + Lo;

    // Apply tone mapping (simulate exposure) and gamma correction.
    color = vec3(1.0) - exp(-color * scene_data.exposure);
    color = pow(color, vec3(1.0 / scene_data.gamma));

    frag_color = vec4(color, 1.0);
}
