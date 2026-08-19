// gfx.jai - 28 Sept 2025
// Shaders n' shit


ShaderSolid :: enum u32 {
	Color;
	ColorNoBlend;
	Smoke;
}

ShaderTexture :: enum u32 {
	Default;
	PalletTint;
}

shader_smoke := Shader.{
	filename = "smoke.glsl",
	alpha_blend = true,
};

shader_pallet_tint := Shader.{
	filename = "pallet_tint.glsl",
	alpha_blend = true,
};


draw_gfx_test :: () {
	//@CLEAN
	//tx := get_texture("T_m_block");
	//x := window_center.x * .25;
	//y := window_center.y;
	//draw_texture(*tx.texture, .{x,y*.25}, .{3,3}, shader=.PalletTint);
	//draw_texture(*tx.texture, .{x,y}, .{10, 10},  shader=.PalletTint);
//
	//tx_pallet := get_texture("T_pallet_0");
	//draw_texture(*tx_pallet.texture, .{x,y*.5}, .{30,30});
}

shader_init :: () {
	log("Reloading shaders.");
	shader_load(*shader_smoke);
	shader_load(*shader_pallet_tint);

	//@TODO  remove the error log spam from the rendering loop
}

shader_load :: (shader : *Shader) {
	path := tprint("%/shaders/%", asset_path, shader.filename);
	buffer, success := read_entire_file(path);
	defer free(buffer);

	if !success {
		log_error("Failed to open %\n", path);
		return;
	}

	log("\tLoading shader [%]", path);
	string_reset(*shader.text);
	shader.text = sprint(buffer);
	shader.gl_handle   = get_shader_program(buffer);
}

set_shader :: (shader := ShaderSolid.Color) {
	if shader== {
		case .Color; 		set_shader_for_color(true);
		case .ColorNoBlend; set_shader_for_color(false);

		//@OPTIMIZE this smoke shader has HORRIBLE performance.
		// went from 900fps -> 200 fps 
		case .Smoke;
			if context.simp.current_shader != *shader_smoke {
		        immediate_set_shader(*shader_smoke);
		        set_projection();

			    t := cast(float32)seconds_since_init();
			    set_uniform(*shader_smoke, "time", t);
		    }
	}
}

set_shader :: (texture : *Texture, shader := ShaderTexture.Default) {
	assert(texture != null);
	if shader== {
		case .Default;
			assert(texture != null);
			set_shader_for_images(texture);

		case .PalletTint;
			//CheckInit();
			immediate_flush();
			if context.simp.current_shader != *shader_pallet_tint {
				immediate_set_shader(*shader_pallet_tint);
		        set_projection();
		    }

	        tx_loc_main := glGetUniformLocation(shader_pallet_tint.gl_handle, "u_diffuse_texture");

		    if tx_loc_main < 0 {
		        log_error("Unable to find 'diffuse_texture' in the current shader.");
		        return;
		    }

		    glActiveTexture(GL_TEXTURE0);
		    glBindTexture(GL_TEXTURE_2D, texture.gl_handle);  // Bind handle to slot 0.
		    glUniform1i(tx_loc_main, 0);

		    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

	        tx_loc_pallet := glGetUniformLocation(shader_pallet_tint.gl_handle, "u_pallet");

		    if tx_loc_pallet < 0 {
		        log_error("Unable to find 'u_pallet' in the current shader.");
		        return;
		    }

		    pallet := get_texture("T_pallet_0");
		    glActiveTexture(GL_TEXTURE0 + 1);
		    glBindTexture(GL_TEXTURE_2D, pallet.texture.gl_handle);
		    glUniform1i(tx_loc_pallet, 1);

		    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	}
	//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	//glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
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

draw_square :: (pos_window : Vector2, size : Vector2, color : Vector4, type := ShaderSolid.Color) {
	set_shader(type);
    h := Vector2.{size.x * .5, 0};
    v := Vector2.{0, size.y * .5};
	p0 := pos_window - h - v;
    p1 := pos_window + h - v;
    p2 := pos_window + h + v;
    p3 := pos_window - h + v;
    immediate_quad(p0, p1, p2, p3, color);
}

draw_box :: (box : Box, color : Vector4, thickness := 2.) {
	t := thickness;
	draw_square(.{box.x + box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x - box.w/2, box.y}, .{t, box.h}, color);
	draw_square(.{box.x, box.y+box.h/2}, .{box.w, t}, color);
	draw_square(.{box.x, box.y-box.h/2}, .{box.w, t}, color);
}

draw_rect :: (r : Rect, color : Vector4)
{
	draw_square(.{r.x+r.w/2.,r.y+r.h/2.}, .{r.w, r.h}, color);
}

// mostly copied from GetRect/color_picker.jai, draw_hsv_circle()
draw_circle :: (center_window : Vector2, radius_outer : float, radius_inner : float = 0, color : Vector4,
		percent_begin := 0.) 
{
	set_shader();
	NUM_SEGMENTS :: 16;
	last_p0, last_p1: Vector2 = ---;

	for i: 0..NUM_SEGMENTS - 1 {
        t := i / cast(float)(NUM_SEGMENTS - 1);

        // start from 12 oclock
        radians := TAU * (t+.25);
        dir := Vector2.{cos(radians), sin(radians)};

        p0 := center_window + dir * radius_outer;
        p1 := center_window + dir * radius_inner;

        // omit percentage of the circle
        if (i != 0 && t > percent_begin) {
        	immediate_triangle(to_vec3(last_p0), to_vec3(last_p1), to_vec3(p1), color, color, color);
            immediate_triangle(to_vec3(last_p0), to_vec3(p1), to_vec3(p0), color, color, color);
        }

        last_p0 = p0;
        last_p1 = p1;
    }
}

draw_collider :: (collider : *Collider, window_pos : Vector2, win_size : Vector2) {
	c := BLUE;
	if collider.type == {
		case .Dynamic; c = MAGENTA;
		case .Trigger; c = YELLOW;
		case .Inactive; c= WHITE;
	}
	if !collider.enabled c = RED;

	p := window_pos;
	if collider.shape== {
		case .Circle; {
			r := win_size.x;
			draw_circle(p, radius_outer=r, radius_inner=r-2, color=c);
		}
		case .Box; {
			box := Box.{p.x, p.y, win_size.x, win_size.y};
			draw_box(box, c);
		}
	}
}

draw_texture :: (texture : *Texture, window_pos : Vector2, scale := Vector2.{1,1}, outline := false, shader := ShaderTexture.Default, tint := WHITE) {
	width := texture.width * scale.x;
	height := texture.height * scale.y;

	if outline {
		draw_box(.{window_pos.x, window_pos.y, width, height}, RED);
	}

	h := Vector2.{width*.5, 0};
    v := Vector2.{0, height*.5};
	p0 := window_pos - h - v;
    p1 := window_pos + h - v;
    p2 := window_pos + h + v;
    p3 := window_pos - h + v;
	set_shader(texture, shader);
    immediate_quad(p0, p1, p2, p3, tint);
}

draw_sprite :: (sprite : *Sprite, window_pos : Vector2, scale := Vector2.{1,1}, use_window_scale := true) {
	if !sprite.initialized return;
	if !sprite.visible return;

	set_shader(sprite.texture, sprite.shader_type);
    
    texW := sprite.texture.width;
    texH := sprite.texture.height;

    frame := sprite.frames[sprite.frame_current];
    subX : float = frame.coords.x;
    subY : float = frame.coords.y;
    subW : float = frame.coords.w;
    subH : float = frame.coords.h;

    uv0x := Vector2.{subX / texW, subY / texH};
    uv1x := Vector2.{(subX+subW) / texW, subY / texH };
    uv2x := Vector2.{(subX+subW) / texW, (subY+subH) / texH};
    uv3x := Vector2.{subX / texW, (subY+subH) / texH};

    ws := ifx use_window_scale then get_window_aspect_scale() else 1.;
    h := Vector2.{frame.coords.w * .5 * ws * scale.x * forced_window_scale_x, 0};
    v := Vector2.{0, frame.coords.h * .5 * ws * scale.y * forced_window_scale_y};

    if sprite.default_flip_x	h *= -1;
    if sprite.flip_x			h *= -1;
    if sprite.default_flip_y	v *= -1;
    if sprite.flip_y			v *= -1;

	p0 := window_pos - h - v + sprite.offset;
    p1 := window_pos + h - v + sprite.offset;
    p2 := window_pos + h + v + sprite.offset;
    p3 := window_pos - h + v + sprite.offset;

    color := sprite.tint * sprite.tint_mult;
    immediate_quad(p0, p1, p2, p3, color, uv0=uv0x, uv1=uv1x, uv2=uv2x, uv3=uv3x);
}


