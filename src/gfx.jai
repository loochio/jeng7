// gfx.jai - 28 Sept 2025
// Shaders n' shit


ShaderType :: enum u8 {
	Color;
	ColorNoBlend;
	Texture;

	Custom;
	CustomBlend;
	Smoke;
}

shader_custom := Shader.{
	filename = "custom.glsl",
	alpha_blend = false,
};

shader_custom_blend := Shader.{
	filename = "custom.glsl",
	alpha_blend = true,
};

shader_smoke := Shader.{
	filename = "smoke.glsl",
	alpha_blend = true,
};


//@CLEAN temp scratch zone while we're figuring this out
shader_draw_test :: () {
	//draw_square_custom(window_center, window_size*0.5, MAGENTA);
	//c := MAGENTA;
	//c.w = 0.5;
	//draw_square_custom(window_center, window_size*0.25, c, .CustomBlend);
	//draw_square_custom(window_center*.5, window_size*0.25, c, .Custom);
	//draw_square_custom(window_center, window_size*0.5, c, .Color);

	//draw_square_custom(window_center, window_size, G_WHITE, .Smoke);
}


shader_init :: () {
	print("Reloading shaders.\n");
	shader_load(*shader_custom);
	shader_load(*shader_custom_blend);
	shader_load(*shader_smoke);

	//@TODO do a DEVELOPER check for attributes/uniform locations
	// remove the error log spam from the rendering loop
}

shader_load :: (shader : *Shader) {
	path := tprint("src/shaders/%", shader.filename);
	buffer, success := read_entire_file(path);
	defer free(buffer);

	if !success {
		print("Failed to open %\n", path);
		return;
	}

	print("\tLoading shader [%]\n", path);
	string_reset(*shader.text);
	shader.text = sprint(buffer);
	shader.gl_handle   = get_shader_program(buffer);
}

set_shader :: (shader : ShaderType, texture : *Texture = null) {
	if shader== {
		case .Color; {
			set_shader_for_color(true);
		}
		case .ColorNoBlend; {
			set_shader_for_color(false);
		}
		case .Texture; {
			assert(texture != null);
			//@TODO
			//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			set_shader_for_images(texture);
		}
		case .Custom; {
			if context.simp.current_shader != *shader_custom {
		        immediate_set_shader(*shader_custom);
		        set_projection();
		        t := cast(float32)seconds_since_init();
			    set_uniform(*shader_custom_blend, "time", t);
			    set_attribute(*shader_custom_blend, "tint", BLUE);
		    }
		}
		case .CustomBlend; {
			if context.simp.current_shader != *shader_custom_blend {
		        immediate_set_shader(*shader_custom_blend);
		        set_projection();

			    t := cast(float32)seconds_since_init();
			    set_uniform(*shader_custom_blend, "time", t);
			    set_attribute(*shader_custom_blend, "tint", BLUE);
		    }
		}

		case .Smoke; {
			if context.simp.current_shader != *shader_smoke {
		        immediate_set_shader(*shader_smoke);
		        set_projection();

			    t := cast(float32)seconds_since_init();
			    set_uniform(*shader_smoke, "time", t);
			    //set_uniform(*shader_smoke, "time", t);
		    }
		}
	}
}

set_uniform :: (shader: *Shader, name: *u8, value : float) {
    loc := glGetUniformLocation(shader.gl_handle, name);
    //if loc < 0   log_error("Unknown uniform: '%'\n", to_string(name));
    if loc >= 0  glUniform1f(loc, value);
}

set_attribute :: (shader: *Shader, name: *u8, value : Vector4) {
    loc := glGetAttribLocation(shader.gl_handle, name);
    //loc := glGetUniformLocation(shader.gl_handle, name);
    //if loc < 0   log_error("Unknown attirbute: '%'\n", to_string(name));
    if loc >= 0  glUniform4f(loc, value.x, value.y, value.z, value.w);
}


/* @CLEAN
SHADER_CUSTOM :: #string END
OUT_IN vec4 iterated_color;

uniform float time;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;
in vec4 tint;

uniform mat4 projection;

void main() {
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color * tint;
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER

out vec4 color;

void main () {
	//color = iterated_color;

	float t = abs(sin(time));
    color = iterated_color * t;
}
#endif // FRAGMENT_SHADER
END

*/
