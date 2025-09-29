// shader.jai - 28 Sept 2025

//immediate_set_shader

shader_init :: () {
	shader_custom.gl_handle   = get_shader_program(SHADER_CUSTOM);
	shader_custom.alpha_blend = false;

	shader_custom_blend.gl_handle   = get_shader_program(SHADER_CUSTOM);
	shader_custom_blend.alpha_blend = true;

	//@CLEAN
	//glUseProgram(shader_custom_blend.gl_handle);
	//time_loc := glGetUniformLocation(shader_custom_blend.gl_handle, "time");
	////time_loc := glGetAttribLocation(shader_custom_blend.gl_handle, "time");
	//if time_loc < 0 print("invalid param %\n", time_loc);
	//else print("found param\n");
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
			set_shader_for_images(texture);
		}
		case .Custom; {
			if context.simp.current_shader != *shader_custom {
		        immediate_set_shader(*shader_custom);
		        set_projection();
		    }
		}
		case .CustomBlend; {
			if context.simp.current_shader != *shader_custom_blend {
		        immediate_set_shader(*shader_custom_blend);
		        set_projection();

		        //shader := state.current_shader;
			    //shader := context.simp.current_shader;
			    
			    shader := *shader_custom_blend;
			    t := cast(float32)seconds_since_init();
			    set_parameter(*shader_custom_blend, "time", t);



			    //loc := glGetUniformLocation(shader.gl_handle, "time");
				//if loc < 0   log_error("Unknown parameter: '%'\n", to_string("time"));
				//if loc >= 0  {
				//	glUniform1f(loc, t);
				//}
//
//
			    //set_parameter(shader, "test", Matrix4.{});

/*
			    gl := shader_custom_blend.gl_handle;
			    time_loc := glGetAttribLocation(gl, "time");
			    print("time_loc %\n", time_loc);
			    if time_loc < 0 print("invalid param");
			    else print("found param\n");

			    context.simp.current_shader = *shader_custom_blend;
    			//backend_use_shader(*shader_custom_blend);
    			glUseProgram(shader_custom_blend.gl_handle);

		        set_projection();
		        */
		    }
		}
	}
}

set_parameter :: (shader: *Shader, name: *u8, value : float) {
    loc := glGetUniformLocation(shader.gl_handle, name);
    if loc < 0   log_error("Unknown parameter: '%'\n", to_string(name));
    if loc >= 0  glUniform1f(loc, value);
}

draw_square_custom :: (pos_window : Vector2, size : Vector2, color : Vector4, type := ShaderType.Custom) {
	set_shader(type);


    h := Vector2.{size.x * .5, 0};
    v := Vector2.{0, size.y * .5};
	p0 := pos_window - h - v;
    p1 := pos_window + h - v;
    p2 := pos_window + h + v;
    p3 := pos_window - h + v;
    immediate_quad(p0, p1, p2, p3, color);
}

shader_draw_test :: () {
	//draw_square_custom(window_center, window_size*0.5, MAGENTA);
	c := MAGENTA;
	c.w = 0.5;
	draw_square_custom(window_center, window_size*0.5, c, .CustomBlend);
	//draw_square_custom(window_center, window_size*0.5, c, .ColorNoBlend);
	//draw_square_custom(window_center, window_size*0.5, c, .Color);
}

ShaderType :: enum u8 {
	Color;
	ColorNoBlend;
	Texture;

	Custom;
	CustomBlend;
}

shader_custom : Shader;
shader_custom_blend : Shader;

SHADER_CUSTOM :: #string END
OUT_IN vec4 iterated_color;

uniform float time;

#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;

uniform mat4 projection;

void main() {
    gl_Position = projection * vec4(vert_position.xy, 0.0, 1.0);
    iterated_color = vert_color;
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
