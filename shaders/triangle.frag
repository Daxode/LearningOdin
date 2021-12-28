#version 450

layout(location = 0) in vec3 fragColor;

layout(location = 0) out vec4 outColor;

vec3 hue_to_rgb(in float H) 
{
    float R = abs(H * 6 - 3) - 1;
    float G = 2 - abs(H * 6 - 2);
    float B = 2 - abs(H * 6 - 4);
    return clamp(vec3(R,G,B),0,1);
}

void main() {
    //outColor = vec4(hue_to_rgb(clamp(sin(max(max(fragColor.r, fragColor.g), fragColor.b)*6.28*1)*0.5+0.5,0,1)), 1);
    //float value = 1-smoothstep(0, 0.05, min(min(fragColor.r, fragColor.g), fragColor.b));
    //outColor = vec4(hue_to_rgb(value), value);
    outColor = vec4(fragColor, 1);
}