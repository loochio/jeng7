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

edit_type := AssetType.Texture;
asset_to_edit : *Asset;

//@CLEAN
//texture_asset : *TextureAsset;
//sprite_asset : *SpriteAsset;


asset_editor_new :: (type : AssetType) {
	if type=={
		case .Texture; asset_to_edit = asset_texture_alloc();
		case .Sprite; asset_to_edit = asset_sprite_alloc();
	}

	//if type=={
	//	case .Texture; texture_asset = asset_texture_alloc();
	//	case .Sprite; sprite_asset = asset_sprite_alloc();
	//}
	edit_type = type;
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
        subwindow_info_view.draw = render_subwindow_view;
        subwindow_info_view.title_text = "Asset View";
    }
};

asset_editor_deinit :: () {
	print("- Asset Editor Deinit -\n");
};

asset_editor_begin :: () {};
asset_editor_end :: () {};
asset_editor_tick :: (dt : float) {};

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


render_subwindow_file_cmds :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	
	draw_asset_btn :: (asset : *Asset, r : Rect, line : s64) {
		p := 4.;
		lh := cast(float)hud_font_pixel_height+p;
		theme := *hud_theme.button_theme;
		theme.alignment = .Left;

		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, asset.name, theme, identifier=line) { 
			asset_to_edit = asset;
			edit_type = asset_to_edit.type;
			print("Editting Asset: %\n", asset_to_edit.name);
		}
	}

	for texture_assets {
		draw_asset_btn(it, r, line);
		//r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		//if button(r0, it.name, theme, identifier=line) { 
		//	asset_to_edit = it;
		//	edit_type = asset_to_edit.type;
		//	print("Editting Asset: %\n", asset_to_edit.name);
		//}
		line += 1;
	}
	for sprite_assets {
		draw_asset_btn(it, r, line);
		line += 1;
	}
}

render_subwindow_view :: (state: *Subwindow_State, r: Rect, data: *void) {
	if asset_to_edit == null return;

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

	{ // save
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		if button(r0, "Save", btn_theme) { asset_save(asset_to_edit); }
		line += 1;
	}

	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w, lh};
		text := tprint("Type: %", asset_to_edit.type);
		label(r0, text, label_theme);
		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		label(r0, "Name", label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		action, text, state := text_input(r1, asset_to_edit.name, *text_theme);
		if action & .ENTERED {
			asset_rename(asset_to_edit, text);
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
		label(r1, asset_to_edit.name, label_theme);

		line += 1;
	}
	{
		r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
		text := tprint("Asset Path:");
		label(r0, text, label_theme);

		r1 := r0;
		r1.x = rd.x+r0.w;
		r1.w = rd.w*0.75;
		label(r1, asset_to_edit.path, label_theme);

		line += 1;
	}

	if edit_type== {
		case .Texture;
			texture_asset := cast(*TextureAsset)asset_to_edit;

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
				}
				line += 1;
			}

			{
				r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
				label(r0, "Absolute Path:", label_theme);

				r1 := r0;
				r1.x = rd.x+r0.w;
				r1.w = rd.w*0.75;
				text := tprint("%/%", img_path, texture_asset.source_path);
				label(r1, text, label_theme);

				line += 1;
			}

			{
				r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
				if button(r0, "Import Source", btn_theme) {
					asset_texture_import(texture_asset);
				}
				line += 1;
			}
			//{
			//	r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
			//	if button(r0, "Save", btn_theme) {
			//		asset_texture_save(texture_asset);
			//	}
			//	line += 1;
			//}
			//{
			//	r0 := Rect.{rd.x, rd.y+rd.h-(lh*line), rd.w*0.25, lh};
			//	if button(r0, "Reload", btn_theme) {
			//		asset_texture_load(texture_asset.name);
			//	}
			//	line += 1;
			//}

			rview := Rect.{r.x+rd.w, r.y, r.w-rd.w, r.h};
			draw_texture(*texture_asset.texture, .{rview.x+rview.w/2., rview.y+rview.h/2.}, scale=.{1,1}, outline=true);

		case .Sprite;
			sprite_asset := cast(*SpriteAsset)asset_to_edit;
	}
}

