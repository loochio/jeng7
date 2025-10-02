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


asset_editor_new :: (type : AssetType) {
	edit_type = type;

	if type=={
		case .Texture; 
			texture_asset = texture_alloc();

		case .Sprite; 
			sprite_asset = sprite_alloc();
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


//@TODO need to render this in a scrollable box
render_subwindow_file_cmds :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme := *hud_theme.button_theme;
	theme.alignment = .Left;
	
	for tx : assets.textures {
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, tx.guid, theme, identifier=line) { 
			texture_asset = tx;
			edit_type = .Texture;
			print("Editting Asset: GUID=%\n", tx.guid);
		}
		line += 1;
	}

	for asset : assets.sprites {
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, asset.name, theme, identifier=line) { 
			sprite_asset = asset;
			edit_type = .Sprite;
			print("Editting Asset: %\n", asset.name);
		}
		line += 1;
	}

	//@CLEAN temp testing, drawing extra entries
	line += 1;
	for 0..10 {
		for asset : assets.textures {
			r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
			if button(r0, asset.guid, theme, identifier=line) { 
				texture_asset = asset;
				edit_type = .Texture;
				print("Editting Asset: GUID=%\n", asset.guid);
			}
			line += 1;
		}
	}
}

render_subwindow_view :: (state: *Subwindow_State, r: Rect, data: *void) {
	if edit_type== {
		case .Texture; 	render_subwindow_view_texture(state, r, data);
		case .Sprite; 	render_subwindow_view_sprite(state, r, data);
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
	draw_square(.{rd.x+rd.w/2., rd.y+rd.h/2.}, .{rd.w, rd.h}, G_BLACK);
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
		action, text, state := text_input(r1, sprite_asset.name, *text_theme);
		if action & .ENTERED {
			sprite_rename(sprite_asset, text);
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
		label(r1, sprite_asset.name, label_theme);

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
	if sprite_asset.texture_asset != null {
		rview := Rect.{r.x+rd.w, r.y, r.w-rd.w, r.h};
		pos := Vector2.{rview.x+rview.w/2., rview.y+rview.h*0.8};
		draw_texture(*sprite_asset.texture_asset.texture, pos, scale=.{1,1}, outline=true);

		spos := Vector2.{pos.x, pos.y-200};
		draw_square(spos, sprite_asset.frame_size, GREY);
		draw_sprite(sprite_asset, spos);
	}
}
