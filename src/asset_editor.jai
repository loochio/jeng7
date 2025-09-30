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
subwindow_info_assets : Subwindow_Info;


asset_editor_init :: () {
	print("+ Asset Editor Init +\n");

	// Init subwindow UI
	{ // asset creation
        r := get_rect(0, xx (window_height-200), 250, 200);
        subwindow_info_assets.rect = r;
        subwindow_info_assets.draw = render_subwindow_assets;
        subwindow_info_assets.title_text = "Asset Creation";
    }
};

asset_editor_deinit :: () {
	print("- Asset Editor Deinit -\n");
};

asset_editor_begin :: () {};
asset_editor_end :: () {};
asset_editor_tick :: (dt : float) {};

asset_editor_render :: (dt : float) {
	win_theme := hud_theme.subwindow_theme;
    if subwindow_info_assets.open {
    	subwindow_state := add_subwindow(*subwindow_info_assets, *win_theme);
    }

    draw_popups();
};


render_subwindow_assets :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme := *hud_theme.button_theme;
	theme.alignment = .Left;

	{ // texture 
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Texture", theme) { asset_editor_new_texture(); }
		line += 1;
	}

	{ // sprite 
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Sprite", theme) { asset_editor_new_sprite(); }
		line += 1;
	}
	{ // sprite controller
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New Sprite Controller", theme) { asset_editor_new_sprite_controller(); }
		line += 1;
	}
	{ // sfx
		r0 := Rect.{r.x, r.y+r.h-(lh*line), r.w, lh};
		if button(r0, "New SFX", theme) { asset_editor_new_sfx(); }
		line += 1;
	}
}

asset_editor_new_texture :: () {
	print("Creating new Texture asset\n");
}

asset_editor_new_sprite :: () {
	print("Creating new SPRITE asset\n");
}

asset_editor_new_sprite_controller :: () {
	print("Creating new SPRITE Controller asset\n");
}

asset_editor_new_sfx :: () {
	print("Creating new SFX asset\n");
}

