#version 450

layout(binding = 1) uniform sampler2D texture_sampler;

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;

layout(location = 0) out vec4 out_color;

void main() {
    out_color = vec4(in_color * texture(texture_sampler, in_uv * 4).rgb, 1);
}
