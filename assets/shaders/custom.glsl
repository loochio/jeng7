// custom.shader - 28 Sept 2025

OUT_IN vec4 iterated_color;

uniform float time;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec4 tint;

uniform mat4 projection;

void main() {
    vec2 pos = vert_position.xy;
    //pos.y *= 2;
    //pos.x *= abs(sin(time));
    //float proj = abs(cos(time));
    //gl_Position = projection * vec4(pos, 0.0, proj);
    gl_Position = projection * vec4(pos, 0.0, 1.0);
    //tint *= 0.2;
    //vec4 tint2 = tint * 0.2;
    //iterated_color = vert_color + tint2;
    iterated_color = vert_color * tint;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER

out vec4 color;

void main () {
	//color = iterated_color;

	//float t = abs(sin(time));
    float t = clamp(time, 0.0, 1.0);
    color = iterated_color * t;
    color = vec4(color.rgb, 0.5);
}
#endif // FRAGMENT_SHADER
