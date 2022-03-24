layout (location = 0) out vec4 out_color;

uniform vec3 u_albedo;

void main()
{
    out_color = vec4(u_albedo, 1.0);
}