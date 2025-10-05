// pallet_tint.shader - 28 Sept 2025
// indexed texture that should lookup its final color from the 1D u_pallet texture

OUT_IN vec2 TexCoords;
OUT_IN vec4 iterated_color;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec2 vert_uv0;

uniform mat4 projection;

void main() {
    TexCoords = vec2(vert_uv0.x, 1.0-vert_uv0.y);
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER
out vec4 color;

uniform sampler2D u_diffuse_texture;
uniform sampler2D u_pallet; //@TODO figure out our 1D sample

void main () {
    vec4 color_tex = texture(u_diffuse_texture, TexCoords);
    float index = color_tex.r * 16.;
    vec4 color_pallet = texture(u_pallet, vec2(index, 0));
    color = color_pallet;
}
#endif // FRAGMENT_SHADER

