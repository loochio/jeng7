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

start_level :: "hub";
editor_level : Level;
editor_camera : Camera;
dirty := false;
level_to_load := "b";

GRID_SIZE :: 32.;
grid_cell_size := GRID_SIZE;
cursor_size := 1;
cursor_snap_to_grid := true;
cursor_box := BoxFloat.{0,0, GRID_SIZE/2., GRID_SIZE/2.};

// UI 
subwindow_info_level 	: Subwindow_Info;
subwindow_info_tools 	: Subwindow_Info;
subwindow_info_details 	: Subwindow_Info;


editor_init :: () {
	print("~~~ Editor init ~~~\n");

	register_tool(*tool_selection);
	register_tool(*tool_actor);
	register_tool(*tool_move);
	tool = tool_selection; //default

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

	for tool_options {
		string_reset(*it);
	}
	array_reset(*tool_options);
}

editor_begin :: () {
	print("~~~ Editor Begin ~~~ start_level=% | editor_level=%\n", start_level, editor_level.name);

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

	// cursor updates
	mv := vec_window_to_editor(mouse_pos_window);

	if cursor_snap_to_grid {
		gx := cast(s64)(mv.x / GRID_SIZE);
		gx2 : float = ifx mv.x >= 0 then gx + 0.5 else gx - 0.5;
		gx2 *= GRID_SIZE;
		cursor_box.x = gx2;

		gy := cast(s64)(mv.y / GRID_SIZE);
		gy2 : float = ifx mv.y >= 0 then gy + 0.5 else gy - 0.5;
		gy2 *= GRID_SIZE;
		cursor_box.y = gy2;
	}
	else {
		cursor_box.x = mv.x;
		cursor_box.y = mv.y;
	}

	// tool keybind/init mapping
	for t : tools {
		if is_input_pressed(t.key){
			tool = t;
			tool_index = cast(s32)it_index;

			if t.proc_init t.proc_init(t);
		}
	}

	if tool.proc_tick tool.proc_tick(*tool, dt);

	// camera panning, @TODO smooth this translation out
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
	grid_cell_size = scalar_to_window(GRID_SIZE) * editor_camera.zoom;
	line := scalar_to_window(8) * editor_camera.zoom;

	//grid
	//@TODO draw these as lines
	g :: 20;
	s := grid_cell_size;
	for i: -g*2..g*2 {
		for j: -g..g {
			draw_box(.{origin.x+ s*i+s/2, origin.y + s*j+s/2, s, s}, G_BLACK);
		}
	}

	// draw spawners
	for editor_level.spawners {
		sprite := get_actor_sprite(it.type);
		pos := vec_editor_to_window(it.position);
		render_sprite(sprite, pos, scale);
	}

	{ //cursor
		cp := vec_editor_to_window(Vector2.{cursor_box.x, cursor_box.y});
		draw_box(.{cp.x, cp.y, grid_cell_size, grid_cell_size}, YELLOW, line);
	}
	
	//@CLEAN debug orgin
	draw_circle(origin, 5, color=GREEN);

	if tool.proc_render tool.proc_render(*tool, dt);

	//~~~~ UI v2 ~~~~~
	win_theme := hud_theme.subwindow_theme;
    if subwindow_info_level.open  subwindow_state := add_subwindow(*subwindow_info_level, *win_theme);
    if subwindow_info_tools.open  subwindow_state := add_subwindow(*subwindow_info_tools, *win_theme);
    if subwindow_info_details.open  subwindow_state := add_subwindow(*subwindow_info_details, *win_theme);

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
	level_save(*editor_level);
	dirty = false;
}

editor_load :: (name : string) {
	if !is_valid_level_name(name) {
		print("Failed to load, level name [%] did not exist\n", name);
		return;
	}

	if is_valid(*editor_level) level_reset(*editor_level);

	success := level_load(name, *editor_level);

	if !success  return;

	//@CLEAN
	//assert(name == editor_level.name, "name=% editor=%", name, editor_level.name);
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
	result.x /= scale;
	result.y /= scale;
	result = result + editor_camera.position;
	return result;
}

// ~~~~~~ TOOLS ~~~~~~


draw_subwindow_tools :: (state: *Subwindow_State, r: Rect, data: *void) {
	// active tool info
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
    {
 	   changed, state := dropdown(r0, tool_options, *tool_index, *hud_theme.dropdown_theme);
 	   tool = tools[tool_index];
    }

    // tool sub-section
    r1 := Rect.{r.x,r.y, r.w, r.h-r0.h};
	if tool.proc_render_in_subwindow tool.proc_render_in_subwindow(*tool, state, r1, data);
}

EditorTool :: struct {
	name : string;
	key : Key_Code;

	proc_init : EditorToolProc;
	proc_tick : EditorToolProc_Tick;
	proc_render : EditorToolProc_Render;
	proc_render_in_subwindow : EditorToolProc_RenderSubWindow;
}

EditorToolProc :: #type (t : *EditorTool);
EditorToolProc_Tick :: #type (t : *EditorTool, dt : float);
EditorToolProc_Render :: #type (t : *EditorTool, dt : float);
EditorToolProc_RenderSubWindow :: #type (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void);

tool : EditorTool; //@CLEAN = tool_actor;
tools : [..] *EditorTool;
tool_options : [..] string;
tool_index : s32;

register_tool :: (tool : *EditorTool) {
	assert(tool != null);
	array_add(*tools, tool);

	tool_text := sprint("%", tool.name);
	array_add(*tool_options, tool_text);
}

// ~~~~ Actor Spawner Tool ~~~~

EditorTool_Actor :: struct {
	#as using tool : EditorTool;

	actor_type : ActorType;
	actor_data : string;
	prev_placement : Vector2;
}

tool_actor :: EditorTool_Actor.{
	name = "Actors",
	key = 65, /*a*/
	proc_tick = tool_tick_actor,
	proc_render = tool_render_actor,
	proc_render_in_subwindow = tool_render_in_subwindow_actor,
};

/* @CLEAN
tool_actor :: EditorTool.{
	name = "Actors",
	key = 65,
	proc_tick = tool_tick_actor,
	proc_render = tool_render_actor,
	proc_render_in_subwindow = tool_render_in_subwindow_actor,
};
*/

//@CLEAN
//tool_actor_type : ActorType; //@CLEAN
//tool_actor_data : string;	//@CLEAN
//tool_actor_prev_placement : Vector2;


tool_tick_actor :: (t : *EditorTool, dt : float) {
	if ui_hit_this_frame return;

	atool := cast(*EditorTool_Actor) t;

	if is_input_pressed(.MOUSE_BUTTON_LEFT) { 
		cp := Vector2.{cursor_box.x, cursor_box.y};
		if atool.prev_placement != cp {
			spawner := ActorSpawner.{
				atool.actor_type,
				//tool_actor_type,  @CLEAN
				cp,
				Vector2.{1,1},
				atool.actor_data,
			};
			array_add(*editor_level.spawners, spawner);
			atool.prev_placement = cp;
			dirty = true;
		}
	}
}

tool_render_actor :: (t : *EditorTool, dt : float) {}

tool_render_in_subwindow_actor :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void) {
	atool := cast(*EditorTool_Actor) t;

	// actor type label
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	rlabel := Rect.{r.x, r.y+r.h-lh, r.w, lh};
	actor := tprint("Actor Type: %", atool.actor_type);
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
    		atool.actor_type = type;
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
		atool.actor_data = sprint(state.text);
    }
}


// ~~~~ Selection Tool ~~~~

tool_selection :: EditorTool.{
	name = "Selection",
	key = 86 /*v*/,
	proc_tick = tool_tick_selection,
	proc_render = tool_render_selection,
	proc_render_in_subwindow = tool_render_in_subwindow_selection,
};

selected_spawner_idxs : [..] s64;
selection_box : BoxFloat;
selection_start : Vector2;
selection_end : Vector2;

get_selection :: (index := 0) -> *ActorSpawner {
	if selected_spawner_idxs.count == 0 return null;
	if index < 0 || index >= selected_spawner_idxs.count return null;

	spawner_idx := selected_spawner_idxs[index];
	return *editor_level.spawners[spawner_idx];
}

has_selection :: () -> bool {
	return selected_spawner_idxs.count > 0;
}

clear_selection :: () {
	array_reset(*selected_spawner_idxs);
	selection_box = BoxFloat.{};
}

tool_tick_selection :: (t : *EditorTool, dt : float) {
	// begin selection
	if is_input_pressed(.MOUSE_BUTTON_LEFT) {
		if !input_mod_shift && !input_mod_ctrl{
			clear_selection();
		}
		selection_box = cursor_box;
		selection_start = Vector2.{cursor_box.x, cursor_box.y};
		selection_end = selection_start;
	}
	// update selection box
	else if is_input_down(.MOUSE_BUTTON_LEFT) {
		selection_end = Vector2.{cursor_box.x, cursor_box.y};
		selection_box.x = selection_start.x + (selection_end.x-selection_start.x)/2.;
		selection_box.y = selection_start.y + (selection_end.y-selection_start.y)/2.;
		selection_box.w = abs((selection_end.x-selection_start.x)) + GRID_SIZE;
		selection_box.h = abs((selection_end.y-selection_start.y)) + GRID_SIZE;
	}

	// complete selection
	if is_input_released(.MOUSE_BUTTON_LEFT) {
		for editor_level.spawners {
			if is_in_box(it.position, selection_box) {
				if input_mod_ctrl { // delete
					array_unordered_remove_by_value(*selected_spawner_idxs, it_index);
				}
				else { // add
					selected_jdx := 0;
					for j, jdx : selected_spawner_idxs {
						if j < it_index {
							selected_jdx = jdx;
							break;
						}
					}
					array_insert_at(*selected_spawner_idxs, it_index, selected_jdx);
				}
			}
		}
		selection_box = BoxFloat.{};
	}

	if is_input_pressed(.DELETE) {
		if has_selection() {
			for selected_spawner_idxs {
				array_unordered_remove_by_index(*editor_level.spawners, it);
			}
			clear_selection();
			dirty = true;
		}
	}
}

tool_render_selection :: (t : *EditorTool, dt : float) {
	 // selection box 
	sp := vec_editor_to_window(Vector2.{selection_box.x, selection_box.y});
	w := scalar_to_window(selection_box.w) * editor_camera.zoom;
	h := scalar_to_window(selection_box.h) * editor_camera.zoom;
	line := scalar_to_window(4) * editor_camera.zoom;
	draw_box(.{sp.x, sp.y, w, h}, CYAN, line);

	// active selection
	for selected_spawner_idxs {
		spawner := editor_level.spawners[it];
		//spawner := get_selection(); @CLEAN
		sp := vec_editor_to_window(spawner.position);
		draw_box(.{sp.x, sp.y, grid_cell_size, grid_cell_size}, MAGENTA, line*0.5);
	}
}

tool_render_in_subwindow_selection :: (t : *EditorTool, state: *Subwindow_State, r: Rect, data: *void) {
	p := 4.;
	lh := cast(float)hud_font_pixel_height+p;
	theme : = hud_theme.label_theme;
	theme.alignment = .Left;
	{
		r0 := Rect.{r.x, r.y+r.h-lh, r.w, lh};
		text := tprint("Cursor: %", Vector2.{cursor_box.x, cursor_box.y});
	    label(r0, text, *theme);

	    r0.y -= lh;
		text = tprint("Selection: %", selection_box);
	    label(r0, text, *theme);
	}
	
	if has_selection() {
		for selected_spawner_idxs {
			spawner := editor_level.spawners[it];
			//spawner := get_selection(); @CLEAN
			line := 3+it_index;
			r0 := Rect.{r.x, r.y+r.h-lh*line, r.w, lh};
			text := tprint("Selection: % [%]", spawner.type, spawner.position);
	    	label(r0, text, *theme);
		}
	}
}


//~~~ Move Tool ~~~

tool_move :: EditorTool.{
	name = "Move",
	key = 77, /*m*/
	proc_tick = tool_tick_move,
};

tool_tick_move :: (t : *EditorTool, dt : float) {
	if is_input_pressed(.ARROW_UP) {
		print("up\n");
	}
	if is_input_pressed(.ARROW_DOWN) {
		print("down\n");
	}
	if is_input_pressed(.ARROW_RIGHT) {
		print("right\n");
	}
	if is_input_pressed(.ARROW_LEFT) {
		print("left\n");
	}
}
