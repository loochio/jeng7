// editor.jai - Game F
// Editor v2 - 19 Sept 2025


editor_plugin := EnginePlugin.{
	name = "editor",
	proc_init 	= editor_init,
	proc_deinit = editor_deinit,
	proc_begin 	= editor_begin,
	proc_end 	= editor_end,
	proc_tick 	= editor_tick,
	proc_render = editor_render,
};

//@CLEAN
start_level :: "hub";
editor_level : Level;


GRID_SIZE :: 32.;
cursor_size := 1;
cursor_snap_to_grid := true;
cursor_box := BoxFloat.{0,0, GRID_SIZE/2., GRID_SIZE/2.};
//cursor_position : Vector2; @CLEAN
editor_camera : Camera;


// UI v2
subwindow_info_level 	: Subwindow_Info;
subwindow_info_tools 	: Subwindow_Info;
subwindow_info_details 	: Subwindow_Info;

level_to_load := "b";
dirty := false;


EditorTool :: struct {
	name : string;
	proc_tick : EditorToolProc_Tick;
	proc_render : EditorToolProc_Render;
	proc_render_in_subwindow : EditorToolProc_RenderSubWindow;
}

EditorToolProc_Tick :: #type (dt : float);
EditorToolProc_Render :: #type (dt : float);
EditorToolProc_RenderSubWindow :: #type (state: *Subwindow_State, r: Rect, data: *void);

tool : EditorTool = tool_actor;


editor_init :: () {
	print("~~~ Editor init ~~~\n");

	register_cmd("save", (args: .. Any) { editor_save(); });
	register_cmd("load", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			path := tprint("%", arg);
			editor_load(path); 
		}
	});
	register_cmd("new", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			name := tprint("%", arg);
			editor_new_level(name); 
		}
	});
	register_cmd("reload", (args: .. Any) { editor_reload(); }); 
	register_cmd("edit_clear", (args: .. Any) { editor_erase_spawners(); } );
	register_cmd("load_prev", (args: .. Any) { 
		//editor_load(prev_level_name); //@CLEAN
	} );


	// Init subwindow UI
	{ // level 
        r := get_rect(0, xx (window_height-120), 600, 120);
        subwindow_info_level.rect = r;
        subwindow_info_level.draw = draw_subwindow_level;
        subwindow_info_level.title_text = "Level";
    }
    { // tools
        r := get_rect(0, 0, 300, window_height/2.);
        subwindow_info_tools.rect = r;
        subwindow_info_tools.draw = draw_subwindow_tools;
        subwindow_info_tools.title_text = "Tools";
    }
    { // details 
        r := get_rect(xx (window_width-300), xx (window_height-300), 300, 300);
        subwindow_info_details.rect = r;
        subwindow_info_details.draw = draw_subwindow_details;
        subwindow_info_details.title_text = "Details";
    }

	editor_begin();
}

editor_deinit :: () {
	print("~~~ Editor Deinit ~~~ Level=%\n", editor_level.name);
	level_reset(*editor_level);
}

editor_begin :: () {
	print("~~~ Editor Begin ~~~ start_level=% | editor_level=%\n", start_level, editor_level.name);

	//@CLEAN
	//level_reset(*editor_level);
	if is_valid_level_name(start_level) {
		editor_load(start_level);
	}
	else {
		editor_new_level(start_level);
	}

	editor_camera.position = .{0,0};
	editor_camera.zoom = 1;
}

editor_end :: () { /*@TODO unused currently*/ }

editor_tick :: (dt : float) {

	// update ui hit tests
	//@TODO there's probably a better global way to check for UI hits
	update_ui_hit(*subwindow_info_tools.rect);
	update_ui_hit(*subwindow_info_level.rect);
	update_ui_hit(*subwindow_info_details.rect);

	mv := vec_window_to_editor(mouse_pos_window);
	
	if cursor_snap_to_grid {
		gx := cast(s64)(mv.x / GRID_SIZE);
		gx2 : float = ifx mv.x >= 0 then gx + 0.5 else gx - 0.5;
		gx2 *= GRID_SIZE;
		//cursor_position.x = gx2; @CLEAN
		cursor_box.x = gx2;

		gy := cast(s64)(mv.y / GRID_SIZE);
		gy2 : float = ifx mv.y >= 0 then gy + 0.5 else gy - 0.5;
		gy2 *= GRID_SIZE;
		//cursor_position.y = gy2 * GRID_SIZE; @CLEAN
		cursor_box.y = gy2;
	}
	else {
		//cursor_position = mv; @CLEAN
		cursor_box.x = mv.x;
		cursor_box.y = mv.y;
	}

	tool.proc_tick(dt);

	//@TODO softcode, define keybind in tool struct
	if is_input_pressed(65 /*a*/) tool = tool_actor;
	if is_input_pressed(86 /*v*/) tool = tool_selection;

	// camera panning, @TODO smooth this out
	if is_input_released(.MOUSE_BUTTON_RIGHT) {
		editor_camera.position = vec_window_to_editor(mouse_pos_window);
	}

	//@OPTIMIZE mouse wheel, grabbing the raw input event, not sure how else to get this mouse wheel
	for event : events_this_frame {
		if event.wheel_delta > 0 editor_camera.zoom += 0.1;
		if event.wheel_delta < 0 editor_camera.zoom = clamp(editor_camera.zoom-0.1, 0.05, editor_camera.zoom);
    }

	// save
	if is_input_pressed(83 /*s*/) && input_mod_ctrl { editor_save(); }

	if is_input_pressed(.F5) {
		set_plugin("game");
		return;
	}
}

editor_render :: (dt : float) {
	origin := vec_editor_to_window(.{0,0});
	scale := Vector2.{editor_camera.zoom, editor_camera.zoom};
	line := scalar_to_window(8) * scale.x;

	//grid
	//@TODO draw these as lines
	size := scalar_to_window(GRID_SIZE) * scale.x;
	g :: 20;
	for i: -g*2..g*2 {
		for j: -g..g {
			draw_box(.{origin.x+ size*i+size/2, origin.y + size*j+size/2, size, size}, G_BLACK);
		}
	}

	// draw spawners
	for editor_level.spawners {
		sprite := get_actor_sprite(it.type);
		pos := vec_editor_to_window(it.position);
		render_sprite(sprite, pos, scale);
	}

	// active selection
	if has_selection() {
		spawner := get_selection();
		sp := vec_editor_to_window(spawner.position);
		draw_box(.{sp.x, sp.y, size, size}, MAGENTA, line*0.5);
	}
	
	//cursor
	cp := vec_editor_to_window(Vector2.{cursor_box.x, cursor_box.y});
	draw_box(.{cp.x, cp.y, size, size}, YELLOW, line);

	//@CLEAN debug orgin
	draw_circle(origin, 5, color=GREEN);

	//~~~~ UI v2 ~~~~~

    if subwindow_info_level.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_level, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }
    if subwindow_info_tools.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_tools, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }
    if subwindow_info_details.open {  // The Subwindow starts open, but pressing the Close button can close it.
        hud_theme.subwindow_theme.resize_controls |= .SNAP;
        subwindow_state := add_subwindow(*subwindow_info_details, *hud_theme.subwindow_theme);
        hud_theme.subwindow_theme.resize_controls &= ~.SNAP;
    }

    draw_popups();
}

draw_subwindow_level :: (state: *Subwindow_State, r: Rect, data: *void) {
	line := 1;
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	{// level name 
		r0 := Rect.{r.x, r.y+r.h-lh, r.w/2., lh};
		level_name := tprint("% %", editor_level.name, ifx dirty then "[*]" else "");
    	label(r0, level_name, *hud_theme.label_theme);
	}
	bw := r.w*.25;
	{ // save 
		r0 := Rect.{r.x+r.w/2., r.y+r.h-(lh*line), bw, lh};
		if button(r0, "Save", *hud_theme.button_theme) { editor_save(); }
	}
	if dirty { // clear/ reload 
		r0 := Rect.{r.x+r.w/2.+bw, r.y+r.h-(lh*line), bw, lh};
		if button(r0, "Clear", *hud_theme.button_theme) { editor_reload(); }
	}

    line += 1;
	{ // load 
		r0 := Rect.{r.x, r.y+r.h-(lh*line)-p, bw, lh};
		if button(r0, "Load", *hud_theme.button_theme) { 
			editor_load(level_to_load);
			level_to_load = ""; //@TODO this doesn't clear our input text, why?
		}

		r1 := Rect.{r0.x+r0.w, r0.y, bw, r0.h};
		if button(r1, "New", *hud_theme.button_theme) { 
			editor_new_level(level_to_load); 
			level_to_load = "";
		}

		text_theme := hud_theme.text_input_theme;
		text_theme.alignment = .Left;
		text_theme.font = hud_font;

		r2 := Rect.{r1.x+r1.w, r1.y, bw*2, r1.h};
		action, text, state := text_input(r2, level_to_load, *text_theme);
		level_to_load = state.text;
		line += 1;
	}
}


draw_subwindow_details :: (state: *Subwindow_State, r: Rect, data: *void) {

	//@TODO render selected_spawner info
	// allow to edit data

}

editor_save :: () {
	print("attempting to save...\n");
	level_save(*editor_level);
	dirty = false;
}

editor_load :: (name : string) {
	if !is_valid_level_name(name) {
		print("Failed to load, level name [%] did not exist\n", name);
		return;
	}

	//@TODO do we bake is_valid into the level_reset?
	if is_valid(*editor_level)
	{
		print("\treseting %\n", name);
		level_reset(*editor_level);
	}

	success := level_load(name, *editor_level);

	if !success  return;

	assert(name == editor_level.name, "name=% editor=%", name, editor_level.name);
	dirty = false;
}

editor_reload :: () {
	name := tprint("%", editor_level.name);
	editor_load(name);
}

editor_erase_spawners :: () {
	if editor_level.spawners.data != null {
		array_reset(*editor_level.spawners);
		dirty = true;
	}
}

editor_new_level :: (name : string) {
	if is_valid_level_name(name) {
		print("Level name already exists [%]\n", name);
		return;
	}

	if is_valid(*editor_level)
		level_reset(*editor_level);

	editor_level.name = sprint(name);
	dirty = true;
	print("Editting new level: %\n", editor_level.name);
}

//@CLEAN
//is_cursor_deadzone :: (pos : Vector2) -> bool {
//	return pos.x < deadzone.x;
//}

vec_editor_to_window :: (v : Vector2) -> Vector2 {
	result := v - editor_camera.position;
	scale := get_window_aspect_scale() * editor_camera.zoom;
	result.x *= scale;
	result.y *= scale;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

vec_window_to_editor :: (v : Vector2) -> Vector2 {
	result := v;
	result.x -= window_width/2.;
	result.y -= window_height/2.;
	scale := get_window_aspect_scale() * editor_camera.zoom;
	//scale /= editor_camera.zoom;
	result.x /= scale;
	result.y /= scale;
	result = result + editor_camera.position;
	return result;
}

draw_subwindow_tools :: (state: *Subwindow_State, r: Rect, data: *void) {
	// active tool info
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	name := tprint("Active Tool: %", tool.name);
    label(r0, name, *hud_theme.label_theme);

    r1 := Rect.{r.x,r.y, r.w, r.h-r0.h};
	tool.proc_render_in_subwindow(state, r1, data);
}

// ~~~ TOOL Defs ~~~

tool_actor :: EditorTool.{
	name = "Actors",
	proc_tick = tool_tick_actor,
	proc_render = tool_render_actor,
	proc_render_in_subwindow = tool_render_in_subwindow_actor,
};

tool_actor_selection : ActorType;
tool_actor_data : string;
tool_actor_prev_placement : Vector2;

selected_spawner_idx := -1;

get_selection :: () -> *ActorSpawner {
	if selected_spawner_idx < 0 || editor_level.spawners.count == 0 {
		return null;
	}
    assert(selected_spawner_idx < editor_level.spawners.count);
	return *editor_level.spawners[selected_spawner_idx];
}

has_selection :: () -> bool {
	return selected_spawner_idx >= 0 && selected_spawner_idx < editor_level.spawners.count;
}

tool_tick_actor :: (dt : float) {
	if ui_hit_this_frame return;

	if is_input_pressed(.MOUSE_BUTTON_LEFT) { 
		cp := Vector2.{cursor_box.x, cursor_box.y};
		if tool_actor_prev_placement != cp{
			spawner := ActorSpawner.{
				tool_actor_selection, 
				cp,
				Vector2.{1,1},
				tool_actor_data,
			};
			array_add(*editor_level.spawners, spawner);

			tool_actor_prev_placement = cp;
			dirty = true;
		}
	}
}

tool_render_actor :: (dt : float) {}

tool_render_in_subwindow_actor :: (state: *Subwindow_State, r: Rect, data: *void) {
	// actor type label
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	rlabel := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	actor := tprint("Actor Type: %", tool_actor_selection);
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
    label(rlabel, actor, *theme);

    // actor pallet, draw buttons for each
    COLUMNS :: 4;
    AB :: 64.;
    root := Rect.{r.x, rlabel.y, AB, AB};
    index := 0;

    // actor buttons
	for enum_values_as_s64(ActorType) {
		type := cast(ActorType)it;

		if !is_valid_actor_spawner(type) continue;

		//@TODO render this button with the sprite
    	//sprite := get_actor_sprite(it.type);
    	textureid := get_actor_tid(type);
    	tex := *get_texture(textureid).texture;
    	assert(tex != null);

    	rbtn := Rect.{0,0, AB,AB};
    	col := (index % COLUMNS) * AB;
    	rbtn.x = root.x + col;
    	row := (index / COLUMNS) * AB;
    	rbtn.y = root.y - row - rbtn.h;
    	if button(rbtn, "", *hud_theme.button_theme, texture=tex, identifier=it) {
    		tool_actor_selection = type;
	    }
	    index +=1;
    }

    //@TODO data input
    { // spawn data text input
    	rows := ((index / COLUMNS)+1) * AB;
    	rdata := Rect.{r.x, root.y-rows-lh*2-p, r.w, lh};

    	r2 := rdata;
    	r2.w *= 0.2;
   		label(r2, "Data", *theme);

		r3 := rdata;
    	r3.w *= 0.8;
    	r3.x += r2.w;
    	text_theme := hud_theme.text_input_theme;
    	action, text, state := text_input(r3, "", *text_theme);
		tool_actor_data = sprint(state.text);
    }
}


tool_selection :: EditorTool.{
	name = "Selection",
	proc_tick = tool_tick_selection,
	proc_render = tool_render_selection,
	proc_render_in_subwindow = tool_render_in_subwindow_selection,
};

tool_tick_selection :: (dt : float) {
	if is_input_pressed(.MOUSE_BUTTON_LEFT) {
		for editor_level.spawners {
			if is_in_box(it.position, cursor_box) {
				selected_spawner_idx = it_index;
				break;
			}
		}
	}

	if is_input_pressed(.DELETE) {
		if has_selection() {
			spawner := get_selection();
			print("delete selection: % %\n", spawner.type, spawner.position);
			array_unordered_remove_by_index(*editor_level.spawners, selected_spawner_idx);
			selected_spawner_idx = -1;
			dirty = true;
		}
	}
}

tool_render_selection :: (dt : float) {}

tool_render_in_subwindow_selection :: (state: *Subwindow_State, r: Rect, data: *void) {
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
	{
		r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
		text := tprint("Cursor: %", Vector2.{cursor_box.x, cursor_box.y});
		
	    label(r0, text, *theme);
	}
	
	if has_selection() {
		spawner := get_selection();
		r0 := Rect.{r.x, r.y+r.h-lh*2, r.w, lh};
		text := tprint("Selection: % [%]", spawner.type, spawner.position);
    	label(r0, text, *theme);
	}
}

