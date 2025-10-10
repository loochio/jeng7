// asset editor plugin - 29 Sept 2025


asset_editor_plugin := EnginePlugin.{
	name = "assets",
	proc_init 	= asset_editor_init,
	proc_deinit = asset_editor_deinit,
	proc_begin 	= asset_editor_begin,
	proc_end 	= asset_editor_end,
	proc_tick 	= asset_editor_tick,
	proc_render = asset_editor_render,
};


// UI 
subwindow_info_mode : Subwindow_Info;
subwindow_info_file_cmds : Subwindow_Info;
subwindow_info_view : Subwindow_Info;

AssetType :: enum u8{
	Texture;
	Sprite;
	Sound;
}

edit_type := AssetType.Texture;

texture_asset : *TextureAsset;
sprite_asset : *Sprite;
sound_asset : *SoundAsset;

sprite_scale : float = 4.0;
file_scroll : float = 0.0;
sprite_shader_index : s32 = 0;
texture_brightness := 1.;

asset_editor_new :: (type : AssetType) {
	edit_type = type;

	if type=={
		case .Texture;  texture_asset = texture_alloc();
		case .Sprite;  	sprite_asset = sprite_alloc();
		case .Sound;  	sound_asset = sound_alloc();
	}
}

asset_editor_start_edit :: (type : AssetType, guid : string) {
	edit_type = type;

	if type=={
		case .Texture;  
			texture_asset = get_texture(guid);

		case .Sprite;  	
			sprite_asset = get_sprite(guid);
			sprite_shader_index = cast(s32)sprite_asset.shader_type;

		case .Sound;  	
			sound_asset = get_sound(guid);
	}
}

asset_editor_save :: () {
	if edit_type=={
		case .Texture;  
			if is_valid(texture_asset.guid)
				texture_save(texture_asset);

		case .Sprite;  	
			if is_valid(sprite_asset.guid)
				sprite_save(sprite_asset);

		case .Sound;
			if is_valid(sound_asset.guid)
				sound_save(sound_asset);
	}
}

asset_editor_init :: () {
	print("+ Asset Editor Init +\n");

	// Init subwindow UI
	{ // asset modes
        r := get_rect(0, xx (window_height-200), 250, 200);
        subwindow_info_mode.rect = r;
        subwindow_info_mode.draw = render_subwindow_mode;
        subwindow_info_mode.title_text = "Asset Mode";
    }
    { // file cmds
        r := get_rect(0, 0, 250, xx(window_height-200));
        subwindow_info_file_cmds.rect = r;
        subwindow_info_file_cmds.draw = render_subwindow_file_cmds;
        subwindow_info_file_cmds.title_text = "Files";
    }
    { // asset view
        r := get_rect(250, 0, xx (window_width-250), xx window_height);
        subwindow_info_view.rect = r;
        subwindow_info_view.title_text = "Asset View";
        subwindow_info_view.draw = render_subwindow_view;
    }
};

asset_editor_deinit :: () {
	print("- Asset Editor Deinit -\n");

	// reset any runtime data on our assets
	for assets.sprites sprite_reset(it);
};

asset_editor_begin :: () {};
asset_editor_end :: () {};

asset_editor_tick :: (dt : float) {
	if sprite_asset != null {
		sprite_tick(sprite_asset, dt);
	}

	// save
	if is_input_pressed(83 /*s*/) && input_mod_ctrl { asset_editor_save(); }
};

asset_editor_render :: (dt : float) {
	// subwindow rendering
	win_theme := hud_theme.subwindow_theme;
    if subwindow_info_mode.open 		{ add_subwindow(*subwindow_info_mode, *win_theme); }
    if subwindow_info_file_cmds.open 	{ add_subwindow(*subwindow_info_file_cmds, *win_theme); }
    if subwindow_info_view.open 		{ add_subwindow(*subwindow_info_view, *win_theme); }
    draw_popups();
};


render_subwindow_mode :: (state: *Subwindow_State, r: Rect, data: *void) {
	layout := VerticalLayout.{ root=.{r.x, r.y, r.w, (cast(float)hud_font_pixel_height+4.)} };
	if button(ui_next(*layout), "New Texture") 	{ asset_editor_new(.Texture); }
	if button(ui_next(*layout), "New Sprite") 	{ asset_editor_new(.Sprite); }
	if button(ui_next(*layout), "New Sound") 	{ asset_editor_new(.Sound); }
}

AssetFilterType :: enum {
	All;
	Textures;
	Sprites;
	Sounds;
}

file_filter_index : s32 = 0;

render_subwindow_file_cmds :: (state: *Subwindow_State, r: Rect, data: *void) {
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme := *hud_theme.button_theme;
	theme.alignment = .Left;

	// category filters
	rcat := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	filters := enum_names(AssetFilterType);
	dropdown(rcat, filters, *file_filter_index, *hud_theme.dropdown_theme);

	// ~~~ Asset File Selection ~~~

	rass := Rect.{r.x, r.y+r.h-(lh*2), r.w, r.h-(lh*2)};
	layout := VerticalLayout.{ root = .{rass.x, rass.y, rass.w, lh }, direction=.Down };

	filter := cast(AssetFilterType)file_filter_index;
	show_all := filter == .All;
	show_textures := show_all || filter==.Textures;
	show_sprites := show_all || filter==.Sprites;
	show_sounds := show_all || filter==.Sounds;

	//state, left_or_top, right_or_bottom, div := slidable_region(r, *hud_theme.slidable_region_theme);
	//region, rin := begin_scrollable_region(rass);

	if show_textures {
		for tx : assets.textures {
			if button(ui_next(*layout), tx.guid, theme, identifier=layout.line) { 
				asset_editor_start_edit(.Texture, tx.guid);
			}
		}
	}
	
	if show_sprites {
		for spr : assets.sprites {
			if button(ui_next(*layout), spr.guid, theme, identifier=layout.line) { 
				asset_editor_start_edit(.Sprite, spr.guid);
			}
		}
	}

	if show_sounds {
		for sfx : assets.sounds {
			if button(ui_next(*layout), sfx.guid, theme, identifier=layout.line) { 
				asset_editor_start_edit(.Sound, sfx.guid);
			}
		}
	}

	//end_scrollable_region(region, rin.x+rin.w, rin.y, *file_scroll);
	//finish(state);
}

render_subwindow_view :: (state: *Subwindow_State, r: Rect, data: *void) {
	if edit_type== {
		case .Texture; 	render_subwindow_view_texture(state, r, data);
		case .Sprite; 	render_subwindow_view_sprite(state, r, data);
		case .Sound; 	render_subwindow_view_sound(state, r, data);
	}
}

render_subwindow_view_texture :: (state: *Subwindow_State, r: Rect, data: *void) {
	if texture_asset == null return;

	lh := cast(float)hud_font_pixel_height+4.;
	hud_theme.label_theme.alignment = .Left;
	text_theme := hud_theme.text_input_theme;
	text_theme.alignment = .Left;

	// details
	rd := Rect.{r.x, r.y, r.w*0.4, r.h};
	draw_rect(rd, G_BLACK);

	layout := GridLayout.{ 
		root=Rect.{rd.x, rd.y, rd.w, lh}, 
		columns=float.[0.20, 0.80],
	};
	ui_grid_init(*layout);

	ui_label(ui_col(*layout, 0), "Asset Type:");
	ui_label(ui_col(*layout, 1), "Texture");
	ui_line(*layout);

	if button(ui_col(*layout, 0), "Save") { texture_save(texture_asset); }
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "GUID");
	{
		action, text, state := text_input(ui_col(*layout, 1), texture_asset.guid, *text_theme);
		if action & .ENTERED { texture_rename(texture_asset, text); }
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Asset Name:");
	ui_label(ui_col(*layout, 1), texture_asset.guid);
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Texture Path:");
	{
		action, text, _ := text_input(ui_col(*layout, 1), texture_asset.source_path, *text_theme);
		if action & .ENTERED {
			string_reset(*texture_asset.source_path);
			texture_asset.source_path = sprint(text);
			texture_load_from_src(texture_asset);
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Source Path:");
	src_txt := tprint("%/%", img_path, texture_asset.source_path);
	ui_label(ui_col(*layout, 1), src_txt);
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Dimension:");
	dim_txt := tprint("% x %", texture_asset.texture.width, texture_asset.texture.height);
	ui_label(ui_col(*layout, 1), dim_txt);
	ui_line(*layout);

	slider(ui_next(*layout), *sprite_scale, 1.0, 30.0, 1.0, *hud_theme.slider_theme, "scale: ", "");
	slider(ui_next(*layout), *texture_brightness, 1.0, 10.0, 0.1, *hud_theme.slider_theme, "brightness: ", "");

	// draw selected texture on the right
	rview := Rect.{r.x+rd.w, r.y, r.w-rd.w, r.h};

	b := texture_brightness;
	tint := Vector4.{b,b,b,b};
	draw_texture(*texture_asset.texture, .{rview.x+rview.w/2., rview.y+rview.h/2.}, .{sprite_scale, sprite_scale}, outline=true, tint=tint);
}

render_subwindow_view_sprite :: (state: *Subwindow_State, r: Rect, data: *void) {
	if sprite_asset == null return;

	// ~~~~~ Left PANEL ~~~~~~
	// details
	txt_th := hud_theme.text_input_theme;
	txt_th.alignment = .Left;
	hud_theme.label_theme.alignment = .Left;

	rd := Rect.{r.x, r.y, r.w*0.4, r.h};
	lh := cast(float)hud_font_pixel_height+4;
	margin := 8.;
	draw_rect(rd, G_BLACK);

	layout := GridLayout.{ 
		root=Rect.{rd.x+margin, rd.y, rd.w-margin*2, lh}, 
		columns=float.[0.25, 0.75],
	};
	ui_grid_init(*layout);

	ui_label(ui_col(*layout, 0), "Asset Type:");
	ui_label(ui_col(*layout, 1), "Texture");
	ui_line(*layout);

	if button(ui_next(*layout), "Save") { sprite_save(sprite_asset); }

	ui_label(ui_col(*layout, 0), "Edit GUID:");
	{
		action, text := text_input(ui_col(*layout, 1), sprite_asset.guid, *txt_th);
		if action & .ENTERED { sprite_set_guid(sprite_asset, text); }
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "GUID:");
	ui_label(ui_col(*layout, 1), sprite_asset.guid);
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Path:");
	ui_label(ui_col(*layout, 1), sprite_asset.path);
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Texture GUID:");
	{
		r := ui_col(*layout, 1);
		//rin := Rect.{r.x,r.y,r.w*0.75,r.h}; @CLEAN
		action, text := text_input(.{r.x,r.y,r.w*0.85,r.h}, sprite_asset.texture_guid, *txt_th);
		if action & .ENTERED { sprite_set_texture_guid(sprite_asset, text); }

		if button(.{r.x+r.w*.85,r.y,r.w*0.15,r.h}, "View") { 
			asset_editor_start_edit(.Texture, sprite_asset.texture_guid); 
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Frame Count:");
	{
		text := tprint("%", sprite_asset.frame_count);
		action, input, state := text_input(ui_col(*layout, 1), text, *txt_th);
		if action & .ENTERED {
			value, success := string_to_int(input);
			if success { sprite_set_frame_count(sprite_asset, value); }
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Frame Width");
	{
		text := tprint("%", sprite_asset.frame_size.x);
		action, input, state := text_input(ui_col(*layout, 1), text, *txt_th);
		if action & .ENTERED {
			value, success := string_to_int(input);
			if success { sprite_set_frame_width(sprite_asset, xx value); }
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Frame Height");
	{
		text := tprint("%", sprite_asset.frame_size.x);
		action, input, state := text_input(ui_col(*layout, 1), text, *txt_th);
		if action & .ENTERED {
			value, success := string_to_int(input);
			if success { sprite_set_frame_height(sprite_asset, xx value); }
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Play Length");
	{
		text := tprint("%", sprite_asset.play_length);
		action, input, state := text_input(ui_col(*layout, 1), text, *txt_th);
		if action & .ENTERED {
			value, success := string_to_float(input);
			if success { sprite_set_play_length(sprite_asset, value); }
		}
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Offset:");
	{
		text := tprint("%", sprite_asset.offset);
		ui_label(ui_col(*layout, 1), text);
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Tint:");
	{
		text := tprint("%", sprite_asset.tint);
		ui_label(ui_col(*layout, 1), text);
	}
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Shader:");
	shaders := enum_names(ShaderTexture);
	dropdown(ui_col(*layout, 1), shaders, *sprite_shader_index, *hud_theme.dropdown_theme);
	sprite_asset.shader_type = cast(ShaderTexture)sprite_shader_index;
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Flix X: %", sprite_asset.default_flip_x);
	if button(ui_col(*layout, 1), "Toggle") { sprite_asset.default_flip_x = !sprite_asset.default_flip_x; }
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Flix Y: %", sprite_asset.default_flip_y);
	if button(ui_col(*layout, 1), "Toggle") { sprite_asset.default_flip_y = !sprite_asset.default_flip_y; }
	ui_line(*layout);

	ui_label(ui_col(*layout, 0), "Loop: %", sprite_asset.loop);
	if button(ui_col(*layout, 1), "Toggle") { sprite_asset.loop = !sprite_asset.loop; }
	ui_line(*layout);

	// ~~~~~ RIGHT PANEL ~~~~~~
	// draw texture and sprite
	rview := Rect.{r.x+rd.w, r.y, r.w-rd.w, r.h};
	rspr := Rect.{rview.x, rview.y+rview.h*.5, rview.w, rview.h*.5};
	draw_rect(rspr, GREY*0.25);

	if sprite_asset.texture_asset != null {
		pos := Vector2.{rspr.x+rspr.w/2., rspr.y+rspr.h*0.8};
		scale := Vector2.{sprite_scale, sprite_scale};
		draw_texture(*sprite_asset.texture_asset.texture, pos, scale=scale, outline=true);

		spos := Vector2.{pos.x, pos.y-200};
		draw_square(spos, sprite_asset.frame_size*scale, GREY);

		draw_sprite(sprite_asset, spos, scale=scale, use_window_scale=false);
	}

	// sprite controls
	rctrl := Rect.{rview.x, rview.y, rview.w, rview.h*.5};
	draw_rect(rctrl, GREY*.5);

	rbtns := Rect.{rctrl.x, rctrl.y, rctrl.w*.2, rctrl.h};
	{
		layout := VerticalLayout.{ root=.{rbtns.x, rbtns.y, rbtns.w, lh} };
		if button(ui_next(*layout), "Reset") { sprite_reset(sprite_asset); }
		if button(ui_next(*layout), "Pause") { sprite_pause(sprite_asset); }
		if button(ui_next(*layout), "Play") { sprite_play(sprite_asset); }
		if button(ui_next(*layout), "Step") { sprite_step(sprite_asset); }

    	slider(ui_next(*layout), *sprite_scale, 1.0, 10.0, 1.0, *hud_theme.slider_theme, "scale: ", "");
	}

	rstats := Rect.{rbtns.x+rbtns.w, rbtns.y, rbtns.w*2, rbtns.h};
	draw_rect(rstats, GREY*0.1);
	{
		layout := VerticalLayout.{ root=.{rstats.x, rstats.y, rstats.w, lh} };
		ui_label(*layout, "Version: %", sprite_asset.VERSION);
		ui_label(*layout, "Frame Current: %", sprite_asset.frame_current);
		ui_label(*layout, "Play Length: %", sprite_asset.play_length);
		ui_label(*layout, "Play Pos: %", sprite_asset.play_position);
		ui_label(*layout, "Play Rate: %", sprite_asset.play_rate);
		ui_label(*layout, "Playing: %", sprite_asset.playing);
		ui_label(*layout, "Visible: %", sprite_asset.visible);
		ui_label(*layout, "flip_x: %", sprite_asset.flip_x);
		ui_label(*layout, "flip_y: %", sprite_asset.flip_y);
		ui_label(*layout, "tint_mult: %", sprite_asset.tint_mult);
		ui_label(*layout, "shader: %", sprite_asset.shader_type);
	}
}


render_subwindow_view_sound :: (state: *Subwindow_State, r: Rect, data: *void) {
	if sound_asset == null return;

	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	btn_theme := *hud_theme.button_theme;
	btn_theme.alignment = .Left;
	label_theme := *hud_theme.label_theme;
	label_theme.alignment = .Left;
	text_theme := hud_theme.text_input_theme;
	text_theme.alignment = .Left;
	text_theme.font = hud_font;

	// details panel
	rdetails := Rect.{r.x, r.y, r.w*.4, r.h};
	layout := VerticalLayout.{ root=.{rdetails.x, rdetails.y+r.h-lh, rdetails.w, lh}, direction=.Down };

	ui_label(*layout, "Asset Type: Sound");

	if button(ui_next(*layout), "Save") { sound_save(sound_asset); }
	
	ui_label(*layout, "GUID: %", sound_asset.guid);
	{
		action, text, state := text_input(ui_next(*layout), sound_asset.guid, *text_theme);
		if action & .ENTERED {
			sound_set_guid(sound_asset, text);
		}
	}
	
	ui_label(*layout, "Asset path: %", sound_asset.path);

	ui_label(*layout, "Sound wav path: %", sound_asset.source_path);
	{
		action, text, state := text_input(ui_next(*layout), sound_asset.source_path, *text_theme);
		if action & .ENTERED {
			string_reset(*sound_asset.source_path);
			sound_asset.source_path = sprint(text);
			sound_resolve(sound_asset);
		}
	}

	ui_line(*layout);
	if button(ui_next(*layout), "Test Sound") { play_sound(sound_asset); }
	if button(ui_next(*layout), "Test Sound by GUID") { play_sound(sound_asset.guid); }
}
