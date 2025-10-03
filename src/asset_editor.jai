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
	SpriteController;
	Sound;
}

edit_type := AssetType.Texture;

texture_asset : *TextureAsset;
sprite_asset : *Sprite;
sound_asset : *SoundAsset;

sprite_scale : float = 4.0;
file_scroll : float = 0.0;



asset_editor_new :: (type : AssetType) {
	edit_type = type;

	if type=={
		case .Texture;  texture_asset = texture_alloc();
		case .Sprite;  sprite_asset = sprite_alloc();
		case .Sound;  sound_asset = sound_alloc();
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
};

asset_editor_begin :: () {};
asset_editor_end :: () {};

asset_editor_tick :: (dt : float) {
	if sprite_asset != null {
		sprite_tick(sprite_asset, dt);
	}
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
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme := *hud_theme.button_theme;
	theme.alignment = .Left;

	{ // texture 
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Texture", theme) { asset_editor_new(.Texture); }
		line += 1;
	}

	{ // sprite 
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Sprite", theme) { asset_editor_new(.Sprite); }
		line += 1;
	}
	{ // sprite controller
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Sprite Controller", theme) { asset_editor_new(.SpriteController); }
		line += 1;
	}
	{ // sfx
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New SFX", theme) { asset_editor_new(.Sound); }
		line += 1;
	}
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
	changed, state := dropdown(rcat, filters, *file_filter_index, *hud_theme.dropdown_theme);

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
				texture_asset = tx;
				edit_type = .Texture;
				print("Editting Texture: GUID=%\n", tx.guid);
			}
		}
	}
	
	if show_sprites {
		for spr : assets.sprites {
			if button(ui_next(*layout), spr.guid, theme, identifier=layout.line) { 
				sprite_asset = spr;
				edit_type = .Sprite;
				print("Editting Sprite: %\n", spr.guid);
			}
		}
	}

	if show_sounds {
		for sfx : assets.sounds {
			if button(ui_next(*layout), sfx.guid, theme, identifier=layout.line) { 
				sound_asset = sfx;
				edit_type = .Sound;
				print("Editting Sound: %\n", sfx.guid);
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

	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	btn_theme := *hud_theme.button_theme;
	btn_theme.alignment = .Left;
	label_theme := *hud_theme.label_theme;
	label_theme.alignment = .Left;
	text_theme := hud_theme.text_input_theme;
	text_theme.alignment = .Left;
	text_theme.font = hud_font;

	// details
	rd := Rect.{r.x, r.y, r.w*0.4, r.h};
	draw_square(.{rd.x+rd.w/2., rd.y+rd.h/2.}, .{rd.w, rd.h}, G_BLACK);
	line=1;

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
		label(r0, "Asset Type: Texture", label_theme);
		line += 1;
	}

	{ // save
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		if button(r0, "Save", btn_theme) { 
			texture_save(texture_asset);
		}
		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "GUID", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		action, text, state := text_input(r1, texture_asset.guid, *text_theme);
		if action & .ENTERED {
			texture_rename(texture_asset, text);
		}
		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		text := tprint("Asset Name:");
		label(r0, text, label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		label(r1, texture_asset.guid, label_theme);

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		text := tprint("Asset Path:");
		label(r0, text, label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		label(r1, texture_asset.path, label_theme);

		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Texture Path:", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		action, text, state := text_input(r1, texture_asset.source_path, *text_theme);
		if action & .ENTERED {
			string_reset(*texture_asset.source_path);
			texture_asset.source_path = sprint(text);
			texture_load_from_src(texture_asset);
		}
		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Source Path:", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		text := tprint("%/%", img_path, texture_asset.source_path);
		label(r1, text, label_theme);

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Dimensions:", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		text := tprint("% x % (px, w X h)", texture_asset.texture.width, texture_asset.texture.height);
		label(r1, text, label_theme);

		line += 1;
	}

	rview := Rect.{r.x+rd.w, r.y, r.w-rd.w, r.h};
	draw_texture(*texture_asset.texture, .{rview.x+rview.w/2., rview.y+rview.h/2.}, scale=.{1,1}, outline=true);
}

//@TODO state of the art copy pasta here...
// we need better UI code
render_subwindow_view_sprite :: (state: *Subwindow_State, r: Rect, data: *void) {
	if sprite_asset == null return;

	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	btn_theme := *hud_theme.button_theme;
	btn_theme.alignment = .Left;
	label_theme := *hud_theme.label_theme;
	label_theme.alignment = .Left;
	text_theme := hud_theme.text_input_theme;
	text_theme.alignment = .Left;
	text_theme.font = hud_font;

	// details
	rd := Rect.{r.x, r.y, r.w*0.4, r.h};
	draw_rect(rd, G_BLACK);

	line=1;

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
		label(r0, "Asset Type: Sprite", label_theme);
		line += 1;
	}

	{ // save
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		if button(r0, "Save", btn_theme) { 
			sprite_save(sprite_asset);
		}
		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Name", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		action, text, state := text_input(r1, sprite_asset.guid, *text_theme);
		if action & .ENTERED {
			sprite_set_guid(sprite_asset, text);
		}
		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		text := tprint("Asset Name:");
		label(r0, text, label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		label(r1, sprite_asset.guid, label_theme);

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		text := tprint("Asset Path:");
		label(r0, text, label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		label(r1, sprite_asset.path, label_theme);

		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Texture GUID:", label_theme);
		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		action, text, state := text_input(r1, sprite_asset.texture_guid, *text_theme);
		if action & .ENTERED {
			string_reset(*sprite_asset.texture_guid);
			sprite_asset.texture_guid = sprint(text);
			sprite_resolve(sprite_asset);
		}
		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*.25, lh};
		label(r0, "Frames:", label_theme);

		r1 := Rect.{rd.x+r0.w, r0.y, rd.w*0.75, r0.h};
		text := tprint("%", sprite_asset.frame_count);
		action, input, state := text_input(r1, text, *text_theme);
		if action & .ENTERED {
			value, success := string_to_int(input);
			if success {
				sprite_asset.frame_count = value;
				sprite_resolve(sprite_asset);
			}
		}

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*.25, lh};
		label(r0, "Frame Size (w,h):", label_theme);

		//x
		r1 := Rect.{rd.x+r0.w, r0.y, rd.w*0.375, r0.h};
		{
			text := tprint("%", sprite_asset.frame_size.x);
			action, input, state := text_input(r1, text, *text_theme);
			if action & .ENTERED {
				value, success := string_to_float(input);
				if success {
					sprite_asset.frame_size.x = value;
					sprite_resolve(sprite_asset);
				}
			}
		}
		//y
		r2 := Rect.{r1.x+r1.w, r1.y, r1.w, r1.h};
		{
			text := tprint("%", sprite_asset.frame_size.y);
			action, input, state := text_input(r2, text, *text_theme);
			if action & .ENTERED {
				value, success := string_to_float(input);
				if success {
					sprite_asset.frame_size.y = value;
					sprite_resolve(sprite_asset);
				}
			}
		}

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*.25, lh};
		label(r0, "Play Length", label_theme);

		r1 := Rect.{rd.x+r0.w, r0.y, rd.w*0.75, r0.h};
		text := tprint("%", sprite_asset.play_length);
		action, input, state := text_input(r1, text, *text_theme);
		if action & .ENTERED {
			value, success := string_to_float(input);
			if success {
				sprite_asset.play_length = value;
				sprite_resolve(sprite_asset);
			}
		}

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
		text := tprint("Offset: %", sprite_asset.offset);
		label(r0, text, label_theme);
		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
		text := tprint("Tint: %", sprite_asset.tint);
		label(r0, text, label_theme);
		line += 1;
	}

	{
		//@TODO don't know why this checkbox isn't rendering the check
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
 		pressed := base_checkbox(r0, "Flip X", sprite_asset.default_flip_x, *hud_theme.checkbox_theme, line);
        if pressed {
        	sprite_asset.default_flip_x = !sprite_asset.default_flip_x;
        	print("flip x %\n", sprite_asset.default_flip_x);
        }

		line += 1;
	}

	{
		//@TODO don't know why this checkbox isn't rendering the check
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
 		pressed := base_checkbox(r0, "Flip y", sprite_asset.default_flip_y, *hud_theme.checkbox_theme, line);
        if pressed {
        	sprite_asset.default_flip_y = !sprite_asset.default_flip_y;
        	print("flip x %\n", sprite_asset.default_flip_y);
        }

		line += 1;
	}

	{
		//@TODO don't know why this checkbox isn't rendering the check
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
 		pressed := base_checkbox(r0, "Loop", sprite_asset.loop, *hud_theme.checkbox_theme, line);
        if pressed {
        	sprite_asset.loop = !sprite_asset.loop;
        	print("loop %\n", sprite_asset.loop);
        }
		line += 1;
	}

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
		draw_sprite(sprite_asset, spos, scale=scale);
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

		ui_label(*layout, "Frame Current: %", sprite_asset.frame_current);
		ui_label(*layout, "Play Pos: %", sprite_asset.play_position);
		ui_label(*layout, "Play Rate: %", sprite_asset.play_rate);
		ui_label(*layout, "Playing: %", sprite_asset.playing);
		ui_label(*layout, "Visible: %", sprite_asset.visible);
		ui_label(*layout, "flip_x: %", sprite_asset.flip_x);
		ui_label(*layout, "flip_y: %", sprite_asset.flip_y);
		ui_label(*layout, "tint_mult: %", sprite_asset.tint_mult);
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
