/* Game F prototype - 13 Sept 2025

Idea: Recusive level warping
Inspirations: Coccoon | Patrick's Parabox

Log: 14 Sept 2025
Inspirations: Inception

14 Sept 2025 from Moonbase420
// Dear maintainer: // 
// Once you are done trying to 'optimize' this routine, 
// and have realized what a terrible mistake that was, 
// please increment the following counter as a warning 
// to the next guy: // 
// total_hours_wasted_here = 42 //

*/

game_plugin := EnginePlugin.{
	name = "game",
	proc_init 	= game_init,
	proc_deinit = game_deinit,
	proc_begin 	= game_begin,
	proc_end 	= game_end,
	proc_tick 	= game_tick,
	proc_render = game_render,
};

game_paused := false;
game_over := false;
input_up := false;
input_down := false;
input_right := false;
input_left := false;

game_init :: () {
	print("~~ Game Init ~~ \n");
	register_cmd("game_restart", (args: .. Any) { game_restart(); });
	game_begin();
}

game_deinit :: () {
	game_end();
	print("~~ Game Deinit ~~\n");
}

game_begin :: () {
	print("~~ Game Begin ~~\n");
	game_over = false;
	game_paused = false;

	w := world_init("level_01");
	for * worlds {
		if !is_valid(it) continue;
		world_begin(it);
	}
	world_spawn_hero(w);

	assert(active_world != null);
	assert(active_world.hero != null);
}

game_end :: () {
	print("~~ Game End ~~\n");

	for worlds {
		if !is_valid(*it) continue;
		world_deinit(*it);
	}
	active_world = null;
}

game_restart :: () {
	print("Game Restart\n");
	game_end();
	game_begin();
}

game_tick :: (dt : float) {
	if is_input_pressed(.TAB) toggle_pause();
	if is_input_pressed(.ENTER) game_restart();
	if is_input_pressed(.F5) {
		set_plugin("editor"); //@TODO build define out?
		return;
	}

	if game_paused  return;
    if game_over  return;

	input_up = is_input_down(87) || is_input_down(.ARROW_UP); //w
	input_down = is_input_down(83) || is_input_down(.ARROW_DOWN); //s
	input_left = is_input_down(65) || is_input_down(.ARROW_LEFT); //a
	input_right = is_input_down(68) || is_input_down(.ARROW_RIGHT); //d

	//@TODO reimplement
	//game_mouse_pos_world = coords_window_to_world(mouse_pos_window, *active_world.camera);

	// Tick root worlds (ones without a parent)
	// we start from the negative active world's depth, 
	// keeping our active world rendered at depth=0
	for worlds {
		if !is_valid(*it) continue;
		if it.parent == null world_tick(*it, dt, -active_world.depth);
	}
}


// ~~~ physics simulation ~~~
PHYSICS_ITERATIONS :: 1;
PHYSICS_SLEEP_THRESHOLD :: 0.0001;
PARTITION_CELL_SIZE :: 75.; // world units, needs to be large enough to cover a collider size
PARTITION_RANGE :: 1;

is_in_partition_range :: (a0 : *Actor, a1 : *Actor) -> bool {
	return abs(a0.partition_cell_x - a1.partition_cell_x) <= PARTITION_RANGE 
		&& abs(a0.partition_cell_y - a1.partition_cell_y) <= PARTITION_RANGE ;
}

get_partition_pos :: (cell_x : s64, cell_y : s64) -> Vector2 {
	return .{ 
		PARTITION_CELL_SIZE * (xx cell_x + 0.5), 
		PARTITION_CELL_SIZE * (xx cell_y + 0.5)
	};
}

get_partition_index_from_world_pos :: (pos : float) -> s64 {
	return xx (pos / PARTITION_CELL_SIZE);
}

pause_physics := false;

physics_step :: (using world : *World, dt : float) {
	if pause_physics return;

	// update pos
	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;

		if distance_squared(a.position, a.prev_position) < PHYSICS_SLEEP_THRESHOLD {
			a.body.asleep = true;
		}
		else {
			a.body.asleep = false;
			a.direction = normalize(a.position - a.prev_position);
		}

		a.prev_position = a.position;

		a.partition_cell_x = get_partition_index_from_world_pos(a.position.x);
		a.partition_cell_y = get_partition_index_from_world_pos(a.position.y);
	}

	// velocity, trigger overlaps 
	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;
		if !a.body.enabled continue;
		if a.body.type == .Static continue;

		a.position.x += a.velocity.x * dt;
		a.position.y += a.velocity.y * dt;
		drag := a.linear_drag * dt;
		if a.velocity.x > 0 {
			a.velocity.x = max(0., a.velocity.x - drag);
		}
		else if a.velocity.x < 0 {
			a.velocity.x = min(0., a.velocity.x + drag);
		}

		if a.velocity.y > 0 {
			a.velocity.y = max(0., a.velocity.y - drag);
		}
		else if a.velocity.y < 0 {
			a.velocity.y = min(0., a.velocity.y + drag);
		}
	}

	// trigger checks, damage
	/*
	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;
		if a.proc_onoverlap_damage == null continue;

		for j : actors_head..actors_tail {
			b := *actors[j];
			if !is_valid(b) continue;
			if a == b continue;
			if !is_in_partition_range(a, b) continue;

			if is_overlap(b.position, *b.body, a.position, *a.damage_collider) {
				a.proc_onoverlap_damage(a,b);
			}
		}
	}*/

	// collision resolution
	for 0..PHYSICS_ITERATIONS 
	{
		for i : actors_head..actors_tail {
			a := *actors[i];
			if !is_valid(a) continue;
			if !a.body.enabled continue;
			if a.body.asleep continue;
			if a.body.type != .Dynamic continue; 

			//@TODO factor in focused partition range (cells around Hero)

			for j : actors_head..actors_tail {
				b := *actors[j];
				if !is_valid(b) continue;
				if a == b continue;
				if !is_in_partition_range(a,b) continue;

				// a is overlapping b, resolve collision, move a out of b
				if is_overlap(a.position, *a.body, b.position, *b.body) {
					//@TODO we're doing this math twice
					apos := a.position;
					ar := a.body.size.x;
					bpos := b.position;
					br := b.body.size.x;
					dv := normalize(apos-bpos);
					dv *= ar + br - distance(apos, bpos); //overlap depth

					//@TODO distribute this move based on size/mass
					if b.body.type == {
						case .Dynamic; {
							a.position += dv/2;
							b.position -= dv/2;
						}
						case .Static; #through;
						case .Kinematic; {
							a.position += dv;
						}
					}

					if a.proc_onhit a.proc_onhit(a,b);
					if b.proc_onhit b.proc_onhit(b,a);
				}
			}
		}
	}
}


toggle_pause :: () {
	game_paused = !game_paused;
	pause_physics = game_paused;
	play_sound(.Pause);
}

game_render :: (dt : float) {
	clip := BoxFloat.{window_width/2., window_height/2., xx window_width, xx window_height};
	//pos_in_window := Vector2.{window_width/2., window_height/2.};
	pos_in_window := Vector2.{0,0};
	world_render(active_world, 0, clip, pos_in_window);

	draw_text :: (line : s64, format_string: string, args: .. Any) {
		text := tprint(format_string, ..args);
		text_width := prepare_text(hud_font, text);
	    text_y := window_height - hud_font.character_height * line;
	    draw_prepared_text(hud_font, 0, text_y, G_WHITE);
	}
	draw_text(1, "[E] Pickup");
	draw_text(2, "[Q] Interact");
	draw_text(3, "[Arrows/WASD] Move");
	draw_text(4, "[TAB] Pause");
	draw_text(5, "[ENTER] Restart");
	draw_text(6, "[F2] Mute");

	draw_text(8, "World: % | D[%] | Age=%", active_world.name, active_world.depth, 
		formatFloat(active_world.age, trailing_width=2));

	//actor count
	draw_actor_count :: true;
	if draw_actor_count {
		count := 0;
		for active_world.actors {
			if is_valid(*it) count += 1;
		}
		draw_text(9, "actors=%", count);
	}

	draw_border :: (color := G_YELLOW, thickness := 100.) {
		draw_square(.{0,window_height/2.}, .{thickness, xx window_height}, color);
		draw_square(.{window_width/2.,0}, .{xx window_width, thickness}, color);
		draw_square(.{window_width/2., xx window_height}, .{xx window_width, thickness}, color);
		draw_square(.{xx window_width, window_height/2.}, .{thickness, xx window_height}, color);
	}

	if game_paused {
		text := "PAUSED";
		text_width := prepare_text(hud_font, text);
		text_x := (window_width - text_width) / 2;
	    text_y := window_height * 0.95;
	    draw_prepared_text(hud_font, text_x, xx text_y, G_BLACK);
	}

	if game_over {
		text := "You are DEAD - [ENTER] respawn";
		text_width := prepare_text(hud_font, text);
		text_x := (window_width - text_width) / 2;
	    text_y := window_height * 0.8;
	    draw_prepared_text(hud_font, text_x, xx text_y, G_RED3);
	}

	debug_draw_pallette :: true;
	if debug_draw_pallette {
		draw_pallet();
	}
}

// ~~~ Worlds ~~~
World :: struct {
	using level : Level;
	flags : WorldFlags;
	depth := 0; // level of nesting
	age := 0.;

	actors : [MAX_ACTORS_PER_WORLD] Actor;
	actors_head := 0;
	actors_tail := 0;

	parent : *World; //@TODO not sure how we're structuring this relationship yet
	//@CLEAN position_in_parent : Vector2; // position in parent space, typically equal to WorldEntrance
	
	//@CLEAN
	//exit_position : Vector2; // movable position where this exit pops to parent

	hero_spawn_index := 0;
	spawn_position : Vector2;
	hero : *Actor; //@TODO remove, looks like we only use this for Markers
	world_transition_time := 0.;
	
	camera : Camera;
	viewport : BoxFloat;
	focus : *Actor;
	focus_default : *Actor;
	render_scale := Vector2.{0.15, 0.15}; // render scale for 1 layer of nesting
}

WorldFlags :: enum_flags u8 {
	Initialized :: 1;
}

MAX_WORLDS :: 8;
worlds : [MAX_WORLDS] World;
MAX_ACTORS_PER_WORLD :: 4096;

active_world : *World;
game_mouse_pos_world : Vector2;

world_init :: (level_name : string, depth := 0) -> *World {
	w : *World;
	for * worlds {
		if is_valid(it) continue;

		w = it;
		w.flags |= .Initialized;
		w.depth = depth;
		w.age = 0.;
		w.actors_head = 0;
		w.actors_tail = 0;
		w.hero_spawn_index = 0;
		w.hero = null;
		w.world_transition_time = 0.;
		w.parent = null;
		break;
	}
	assert(w != null);

	level_load(level_name, *w.level);
	print("World initialize: % [%]\n", w.name, w);

	// warps, linking worlds
	for w.warps {
		print("recursive world init: %\n", it.level_name);
		assert(is_valid(it.level_name));
		world_init(it.level_name, depth+1);
	}

	return w;
}

is_valid ::(world : *World) -> bool {
	return world.flags & .Initialized != 0;
}

world_deinit :: (using world : *World) {
	level_reset(*level);
	flags = 0;

	for * actors {
		destroy(it);
	}
}

world_begin :: (world : *World) {
	assert(is_valid(world));
	for world.spawners {
		a := spawn(world, it.type, it.position);
		assert(a != null);
	}
	assert(world.hero_spawn_points.count > 0);
	world.spawn_position = world.hero_spawn_points[world.hero_spawn_index];

	// warps, linking worlds
	for world.warps {
		assert(is_valid(it.level_name));
		entrance := spawn(world, .WorldEntrance, it.position);
		entrance.child_world = get_world(it.level_name);
		entrance.child_world.parent = entrance.world;
	}
}

world_spawn_hero :: (world : *World) {
	assert(world.hero == null);
	world.hero = spawn(world, .Hero, world.spawn_position);
	world_enter(world.hero, world);
}

get_world :: (name : string) -> *World{
	for * worlds {
		if !is_valid(it) continue;
		if it.name == name  return it;
	}
	assert(false, "failed to find world [%]\n", name);
	return null;
}

// Convert a vector in the given world space
// replacing coords_world_to_window() to accommadate new world system
vec_world_to_window :: (world_pos : Vector2, world : *World, nests := 0) -> Vector2 {
	result := world_pos - world.camera.position;
	scale := get_window_aspect_scale();
	scale *= get_nest_scale(nests);
	result.x *= scale;
	result.y *= scale;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

world_enter :: (a : *Actor, world : *World) {
	pos := Vector2.{};

	//@FIX warp to the pos of target world's exit, wait what?
	for world.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(*it) continue;

		if it.type == .WorldExit {
			pos = it.position;
			break;
		}
	}
	world_warp(a, world, pos);
}

world_exit :: (a : *Actor) {
	assert(a != null);
	assert(a.world.parent != null);

	// set the focus of this exiting world
	for * a.world.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(it) continue;

		// set our focus to the exit
		if a.type == .Hero && it.type == .WorldExit {
			a.world.focus = it;
			break;
		}
	}

	// warp to the parent entrance position
	pos := Vector2.{};
	for * a.world.parent.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(it) continue;

		if it.type == .WorldEntrance && a.world == it.child_world {
			pos = it.position;
			break;
		}
	}
	world_warp(a, a.world.parent, pos);
}

world_warp :: (a : *Actor, world : *World, pos := Vector2.{}) {
	assert(is_valid(world));
	assert(is_valid(a));
	assert(a.type == .Hero);

	print("warping to world: % | actor=%\n", world.name, a.type);
	active_world = world;
	move_actor_to_world(a, active_world, pos);
}

move_actor_to_world :: (actor : *Actor, world : *World, pos := Vector2.{}) -> *Actor{
	if actor.world == world {
		print("attempting to reenter world=% with actor=% flags=%\n", world.name, actor.type, actor.flags);
		return null;
	}
	print("attemping move world=% : [%] % \n", world.name, actor, actor.type);

	// force blocked items to drop before we start moving memory between worlds
	item := actor.held_item;
	if item != null && (item.flags & .BlockWarping != 0) {
		print("force dropping item=% | flags=%\n", item.type, item.flags);
		item_drop(actor);
		item = null;
	}

	assert(actor.world != world);
	new_actor := init_actor(world);
	memcpy(new_actor, actor, size_of(Actor));

	// we need to reset the world bc it gets overwritten with memcpy()
	new_actor.world = world;
	new_actor.position = pos;

	if item != null {
		i := move_actor_to_world(item, world);
		item_pickup(i, new_actor);
	}

	if new_actor.type == {
		case .Hero; {
			world.focus = new_actor;
			world.hero = new_actor;
			world.world_transition_time = .25;
			active_world = world;
		}
		case .WorldEntrance; {
			// update the linked worlds along with their depth (level of nesting)
			new_actor.child_world.parent = world;
			new_actor.child_world.depth = world.depth+1;
		}
	}

	//@TODO reattach children
	//for child : children {
	//	print("moving child: type:% \n", child.type);
	//	c := move_actor_to_world(child, world);
	//	attach(a, c, c.relative_position);
	//}

	// cleanup the old actor now that we're done with it
	deinit_actor(actor);
	return new_actor;
}

world_tick :: (using world : *World, dt : float, nests := 0) {
	assert(is_valid(world));

	// Time dilation, time moves slower in nested worlds (think Inception)
	pure_dt := dt;
	nest_scale := get_nest_scale(nests);
	dt *= 1/nest_scale;
	age += dt;

    // cam lerp 
    camera.zoom = nest_scale;
    if focus != null {
    	fp := focus.position;
		dist := distance(camera.position, fp);
		if dist > 0.1 {
		    camera.position = lerp(camera.position, fp, dt);
		}
		else {
			camera.position = fp;
		}
    }
	else {
		camera.position.x = 0;
		camera.position.y = 0;
	}
	
	//@TODO this only works for entrace, need to do somethign for exit
	if world_transition_time > 0 {
		world_transition_time -= dt;

		if world_transition_time <= 0 {
			world_transition_time = 0;
		}
		return;
	}

	physics_step(world, dt);

    for i : actors_head..actors_tail {
		a := *actors[i];
    	if !is_valid(a) continue;

    	if (a.proc_tick) {
    		// kind of sloppy that we have to check this but code below might be invalid 
    		if game_over return;

    		a.proc_tick(a, dt);
    	}

    	a.sprite.flipped = a.direction.x < 0;
		sprite_tick(*a.sprite, dt);
    	
    	a.lifetime_dt += dt;
		if a.lifetime > 0 && a.lifetime_dt >= a.lifetime {
			if a.proc_onlifetime_expired
				a.proc_onlifetime_expired(a);

			print("LIFETIME EXPIRATION type=%\n", a.type);
			destroy(a);
		}

		/* @TODO redo markers
    	if a.marker {
    		assert(xx(a.flags & .Pickupable));
			a.marker.sprite.visible = false;

			//@OPTIMIZE use spatial partition 
			//@TODO could generalize this to all actors
			// but keeping to the Hero for speed
			h := active_world.hero;
			assert(h != null);
			holding := is_holding_item(h);
			if !holding && is_overlap(a.position, *a.body, h.position, *h.interact_collider){
				a.marker.sprite.visible = true;
			}
		}
		*/

		for child : a.children {
			child.position = a.position;
			child.position += child.relative_position;
		}
    }

    // recursive world ticks, tick child worlds
    for actors {
    	if !is_valid(*it) continue;
    	if it.child_world == null continue;

    	// passing pure_dt because we continue to do nested scaling later
    	world_tick(it.child_world, pure_dt, nests+1);
    }
}

WORLD_NESTED_SCALE :: 0.25;
WORLD_NESTED_SCALE_VEC :: Vector2.{WORLD_NESTED_SCALE, WORLD_NESTED_SCALE};

get_nest_scale :: (nests := 0) -> float {
	return pow(WORLD_NESTED_SCALE, cast(float)nests);
}

get_nest_scale_vec :: (nests := 0) -> Vector2 {
	scale := get_nest_scale(nests);
	return Vector2.{scale, scale};
}

get_nest_color :: (nests : s64) -> Vector4 {
	return lerp(BLUE, RED, nests / 3.);
}

world_render :: (using world : *World, nests : s64, window_clip : BoxFloat, pos_in_window : Vector2) {
	assert(is_valid(world), "%", world.name);

	nscale := get_nest_scale_vec(nests);
	{
		x0 := cast(s32)(window_clip.x - window_clip.w/2.);
		y0 := cast(s32)(window_clip.y - window_clip.h/2.);
		x1 := cast(s32)(window_clip.x + window_clip.w/2.);
		y1 := cast(s32)(window_clip.y + window_clip.h/2.);
		set_scissor(x0,y0,x1,y1);
	}
	
	// sprite rendering, sorted by position.y
	sorted_actors : [..] *Actor;

	for i : actors_head..actors_tail {
		a := *actors[i];
		if !is_valid(a) continue;

		if ENABLE_FRUSTRUM_CULLING
		{
			//skip entities not in view
			//@TODO prob not precise with all of sprite's variables
			ep := vec_world_to_window(a.position, world, nests);
			ew := a.sprite.size.x;
			eh := a.sprite.size.y;
			if ep.x < -ew || ep.x > (window_width+ew) || ep.y < -eh || ep.y > (window_height+eh) 
				continue;
		}
		
		idx := 0;
		for sorted_actors {
			if a.sprite.layer > it.sprite.layer {
				idx += 1;
				continue;
			}
			if a.sprite.layer < it.sprite.layer {
				break;
			}
			// factor in relative offset if attached to parent
			ya := a.position.y - a.relative_position.y;
			yb := it.position.y - it.relative_position.y; 
			if ya < yb {
				idx += 1;
				continue;
			}
		}
		array_insert_at(*sorted_actors, a, idx);
	}

	// sprite rendering
	for a : sorted_actors {
		assert(is_valid(a));

		// inlining vec_world_to_window() for clarity
		pos := a.position - world.camera.position;
		scale := get_window_aspect_scale();
		scale *= get_nest_scale(nests);
		pos.x *= scale;
		pos.y *= scale;
		pos.x += window_width/2.;
		pos.y += window_height/2.;
		pos += pos_in_window; // recursively add our pos

		render_sprite(*a.sprite, pos, nscale);
	}

	// clear the scissor now so we can set a new one in our recursive render_entrance() call
	clear_scissor();

	// recursive actor rendering, only for render_entrance(..) for now.
	//@OPTIMIZE copy-pasta on pos calc
	for a : sorted_actors {
		if a.proc_render {
			pos := vec_world_to_window(a.position, world, nests);
			pos += pos_in_window; // recursively add our pos
			a.proc_render(a, nests, window_clip, pos);
		}
	}

	//@OPTIMIZE move this to an array_reset_safe(..) type of func
	if sorted_actors.data != null
		array_reset(*sorted_actors);
}

ENTRANCE_CLIP_SIZE :: 80.;

render_entrace := (a : *Actor, nests : s64, window_clip : BoxFloat, pos_in_window : Vector2) {
	// find new clipping box, subdividing our current window_clip
	subclip : BoxFloat;
	subclip.x = pos_in_window.x;
	subclip.y = pos_in_window.y;
	nscale := get_nest_scale(nests);
	box_size := ENTRANCE_CLIP_SIZE * nscale;
	subclip.w = box_size;
	subclip.h = box_size;

	overlapping, intersection := get_box_intersection(window_clip, subclip);
	
	if overlapping {
		//scuffed eps check
		assert(intersection.w <= subclip.w+1. && intersection.h <= subclip.h+1., 
			"nests=% | win=% | sub=% | intersection=%", nests, window_clip, subclip, intersection);

		//@TODO render this as an outline sprite
		//{
		//	color := get_nest_color(a.world.depth);
		//	thickness := scalar_to_window(4.) * nscale;
		//	outline : BoxFloat;
		//	outline.x = pos_in_window.x;
		//	outline.y = pos_in_window.y;
		//	outline.w = box_size;
		//	outline.h = box_size;
		//	draw_box(outline, color, thickness);
		//}
		
		origin := pos_in_window;
		origin.x -= window_width/2.;
		origin.y -= window_height/2.;
		world_render(a.child_world, nests+1, intersection, origin);
	}
}


// Holding World data for spawning actors
Level :: struct {
	name : string;
	spawners : [..] ActorSpawner;
	hero_spawn_points : [..] Vector2;
	warps : [..] WarpSpawner;
}

ActorSpawner :: struct {
	type : ActorType;
	position : Vector2;
}

WarpSpawner :: struct {
	position : Vector2;
	level_name : string;
}

// There's a simple enum serialization example in how_to/013_enums.jai
level_save :: (level : *Level) {
	path := tprint("levels/%.level", level.name);
	builder: String_Builder;
	init_string_builder(*builder);

	// level name
	name_len := cast(*u8)*level.name.count;
	append(*builder, name_len, size_of(s64));
	append(*builder, level.name);

	{ // level spawners
		count := cast(*u8)*level.spawners.count;
		append(*builder, count, size_of(s64));
		for * level.spawners {
			data := cast(*u8)it;
			append(*builder, data, size_of(ActorSpawner));
		}
	}
	{ // hero spawn points
		count := cast(*u8)*level.hero_spawn_points.count;
		append(*builder, count, size_of(s64));
		for * level.hero_spawn_points {
			data := cast(*u8)it;
			append(*builder, data, size_of(Vector2));
		}
	}
	{ // warps
		count := cast(*u8)*level.warps.count;
		append(*builder, count, size_of(s64));
		for * level.warps {
			data := cast(*u8)it;
			append(*builder, data, size_of(WarpSpawner));

			// level name
			len := cast(*u8)*it.level_name.count;
			append(*builder, len, size_of(s64));
			append(*builder, it.level_name);
		}
	}

	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);
}

level_load :: (name : string, level : *Level) -> bool {
	path := tprint("levels/%.level", name);
	buffer, success := read_entire_file(path);

	if !success {
		print("Failed to load level: %\n", path);
		return false;
	}

	// Level should have been freed before hand
	assert(level.name.count == 0, "%", level.name); //@CLEAN
	assert(level.spawners.count == 0 && level.spawners.data == null);
	assert(level.hero_spawn_points.count == 0 && level.hero_spawn_points.data == null);

	// name
	name_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*name_len, size_of(s64));
	level.name = alloc_string(name_len);
	consume_u8_and_length(*buffer, level.name.data, name_len);

 	// spawners
	spawner_len := 0;
	consume_u8_and_length(*buffer, cast(*u8)*spawner_len, size_of(s64));
	assert(level.spawners.count == 0);
	for 0..spawner_len-1 {
		spawner := array_add(*level.spawners);
		consume_u8_and_length(*buffer, cast(*u8)spawner, size_of(ActorSpawner));

		low, high := enum_range(ActorType);
		type : s64 = xx spawner.type;
		assert(type >= low, "%", type);
		assert(type <= high, "%", type);
	}

	// hero spawn points
	points := 0;
	consume_u8_and_length(*buffer, cast(*u8)*points, size_of(s64));
	assert(level.hero_spawn_points.count == 0);
	for 0..points-1 {
		p := array_add(*level.hero_spawn_points);
		consume_u8_and_length(*buffer, cast(*u8)p, size_of(Vector2));
	}

	// warps
	warp_count := 0;
	consume_u8_and_length(*buffer, cast(*u8)*warp_count, size_of(s64));
	assert(level.warps.count == 0);
	for 0..warp_count-1 {
		w := array_add(*level.warps);
		consume_u8_and_length(*buffer, cast(*u8)w, size_of(WarpSpawner));

		lvl_name_len := 0;
		consume_u8_and_length(*buffer, cast(*u8)*lvl_name_len, size_of(s64));
		w.level_name = alloc_string(lvl_name_len);
		consume_u8_and_length(*buffer, w.level_name.data, lvl_name_len);

		print("load warp: % name=% pos=%\n", w, w.level_name, w.position);
	}

	print("LOAD attempt: name=% | spawner_len=% | hero_points=% warps=%\n", level.name, spawner_len, points, level.warps);
	return true;
}

level_reset :: (level : *Level) {
	assert(is_valid(level));
	assert(level.name.count > 0);
	string_reset(*level.name);

	if level.spawners.data != null
		array_reset(*level.spawners);

	if level.hero_spawn_points.data != null
		array_reset(*level.hero_spawn_points);

	if level.warps.data != null
		array_reset(*level.warps);
}

is_valid :: (level : *Level) -> bool {
	return level.name.count > 0;
}

// ~~~ end Level ~~~

Actor :: struct {
	type := ActorType.EMPTY;
	flags : ActorFlags;
	world : *World;
	child_world : *World;

	proc_begin : ActorProc;
	proc_tick : ActorProc_Tick;
	proc_render : ActorProc_Render;
	proc_on_interact : ActorProc_Overlap;
	proc_on_dropped : ActorProc;
	proc_on_pickup : ActorProc;

	sprite : Sprite;

	position : Vector2;
	prev_position : Vector2;
	partition_cell_x := 0;
	partition_cell_y := 0;

	direction : Vector2;
	velocity : Vector2;

	body : Collider;
	proc_onhit : ActorProc_Overlap;
	linear_drag := 800; 	// linear reduction in velocity on each tick
	bounce := 0.5; 			// amount we bounce off a collision
	scale := Vector2.{1,1}; //@TODO do we use this?

	speed := Vector2.{1,1};
	interact_collider : Collider;
	proc_onoverlap_interact : ActorProc_Overlap;

	lifetime := -1.;
	lifetime_dt := 0.;
	proc_onlifetime_expired : ActorProc;

	held_item : *Actor;

	//@TODO redo marker logic
	//marker : *Actor;

	children : [..]*Actor;
	parent : *Actor;
	relative_position : Vector2;
}

ActorType :: enum s64 #specified {
	EMPTY 		:: -1; // should never be serialized, using for world.actor mem

	Hero		:: 0;
	Marker		:: 1;
	Tile 		:: 2;
	Tile_Red 	:: 3;
	WorldEntrance :: 4;
	WorldExit 	:: 5; // warps to the parent world
	Key 		:: 6;
}

ActorFlags :: enum_flags s64 {
	Initialized		:: 1;
	Spawnable		:: 1<<1; //@TODO not used?

	CanPickup		:: 1<<19;
	Pickupable		:: 1<<20;
	BlockWarping	:: 1<<21; // VERY IMPORTANT for exits or else the game logically doesn't make sense
}


ActorProc :: #type (actor : *Actor);
ActorProc_Tick :: #type (actor : *Actor, dt : float);
ActorProc_Render :: #type (actor : *Actor, nests : s64, clip : BoxFloat, pos_in_window : Vector2);
ActorProc_Overlap :: #type (a0 : *Actor, a1 : *Actor);

is_valid :: (actor : *Actor) -> bool{
	return actor.type != .EMPTY && actor.flags & .Initialized != 0;
}

init_actor :: (world : *World) -> *Actor{
	// find available memory in our world
	a : *Actor;
	while a == null {
		//reached the end of our static allocs
		//@TODO I'm not sure what I want to do here yet
		assert(world.actors_tail < MAX_ACTORS_PER_WORLD);
		a = *world.actors[world.actors_tail];
		world.actors_tail += 1;

		if is_valid(a) {
			continue;
		}

		a.world = world;
		a.flags |= .Initialized;
		break;
	}
	assert(a != null);
	return a;
}

deinit_actor :: (a : *Actor) {
	a.type = .EMPTY;
	a.flags = 0;
}

spawn :: (world : *World, type : ActorType, pos := Vector2.{0,0}) -> *Actor{
	a := init_actor(world);
	a.type = type;
	a.sprite = get_actor_sprite(a.type);
	a.position = pos;

	//@TODO this is an error prone list of variables to reset
	a.lifetime = -1;
	a.lifetime_dt = 0.;
	
	if a.type == {
		case .Hero; {
			a.speed = .{50,50};
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn | .Hero;
			a.body.collides_with = .Wall | .Pawn;
			a.interact_collider.type = .Trigger;
			a.interact_collider.size = .{22,22};
			a.interact_collider.is_a = .Pawn;
			a.interact_collider.collides_with = .Pawn;

			a.world.focus = a;

			a.proc_tick = (a : *Actor, dt : float) {
				assert(a.world == active_world, "world=%, active=%", a.world.name, active_world.name);
				assert(a.type == .Hero);

				// movement
				dv : Vector2;
			    if input_up  dv.y += 1.;
			    if input_down dv.y -= 1.;
			    if input_right dv.x += 1.;
			    if input_left dv.x -= 1.;

				a.position.x += dv.x * a.speed.x * dt;
				a.position.y += dv.y * a.speed.y * dt;

			    // item pickups
			    if is_input_pressed(69) { //E
			    	if a.held_item {
			    		item_drop(a);
			    	}
			    	else
			    	{
			    		w := a.world;
			    		for i : w.actors_head..w.actors_tail {
							b := *w.actors[i];
				    		if !is_valid(b) continue;
				    		if b.flags & .Pickupable == 0 continue;
				    		if !is_in_partition_range(a, b) continue;

				    		if is_overlap(a.position, *a.interact_collider, b.position, *b.body) {
				    			item_pickup(b, a);

				    			// pickup our first one
				    			//@TODO refine this to base on direction
				    			break;
				    		}
				    	}
			    	}
		    	}
			    // Interact
		    	if is_input_pressed(81) { //Q
					w := a.world;
		    		for i : w.actors_head..w.actors_tail {
						b := *w.actors[i];
			    		if !is_valid(b) continue;
			    		if b.flags & .Pickupable == 0 continue;
			    		if !is_in_partition_range(a, b) continue;

			    		if is_overlap(a.position, *a.interact_collider, b.position, *b.body) {
			    			interact(b, a);
			    			break;
			    		}
			    	}
		    	}
			}
		}

		case .WorldEntrance; {
			a.flags |= .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{8,8};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				print("% interacted with %\n", interactor.type, a.type);
				world_enter(interactor, a.child_world);
			}

			//@CLEAN
			//a.proc_tick = (a : *Actor, dt : float) {
			//	a.child_world.position_in_parent = a.position;
			//}

			a.proc_render = render_entrace; 
			
			/*
			a.proc_render = (a : *Actor, nests : s64, window_clip : BoxFloat, pos_in_window : Vector2) {
				render_entrace(a, nests, window_clip, pos_in_window); 

				nscale := get_nest_scale(nests);
				color := get_nest_color(a.world.depth);
				thickness := scalar_to_window(4.) * nscale;
				outline : BoxFloat;
				outline.x = pos_in_window.x;
				outline.y = pos_in_window.y;
				box_size := ENTRANCE_CLIP_SIZE * nscale;
				outline.w = box_size;
				outline.h = box_size;
				draw_box(outline, color, thickness);
			}*/


			//@CLEAN
			//a.proc_render = _old_proc_render_entrace;

			//@CLEAN
			//ENTRANCE_CLIP_SIZE :: 80.;

/*
			proc_render_entrace := (a : *Actor, nests : s64, window_clip : BoxFloat, pos_in_window : Vector2) {
				entrance_pos := vec_world_to_window(a.position, a.world, nests);

				//epos := a.position - a.world.camera.position;
				//scale := get_window_aspect_scale();
				//scale *= get_nest_scale(nests); 
				//epos.x *= scale;
				//epos.y *= scale;
				//epos.x += window_width/2.;
				//epos.y += window_height/2.;
				//entrance_pos += pos_in_window;


				//entrance_pos := vec_world_to_window(a.position, a.world, 0);

				subclip : BoxFloat;
				subclip.x = entrance_pos.x;
				subclip.y = entrance_pos.y;
				nscale := get_nest_scale(nests);
				box_size := ENTRANCE_CLIP_SIZE * nscale;
				subclip.w = box_size;
				subclip.h = box_size;

				// draw subclip
				{
					color := lerp(YELLOW, RED, nests / 3.);
					thickness := scalar_to_window(2.) * nscale;
					draw_box(subclip, color, thickness);
				}
				
				overlapping, intersection := get_box_intersection(window_clip, subclip);
				if overlapping {
					//scuffed eps check
					assert(intersection.w <= subclip.w+1. && intersection.h <= subclip.h+1., 
						"nests=% | win=% | sub=% | intersection=%", nests, window_clip, subclip, intersection);

					origin := entrance_pos;
					//origin := entrance_pos + pos_in_window;
					origin.x -= window_width/2.;
					origin.y -= window_height/2.;

					world_render(a.child_world, nests+1, intersection, origin);

					color := get_nest_color(a.world.depth);
					thickness := scalar_to_window(4.) * nscale;
					outline : BoxFloat;
					outline.x = entrance_pos.x;
					outline.y = entrance_pos.y;
					outline.w = box_size;
					outline.h = box_size;
					draw_box(outline, color, thickness);
				}

			}
			*/

			//@CLEAN old solution
			/*
			_old_proc_render_entrace := (a : *Actor, nests : s64, pos_in_window : Vector2) {
				// draw a box in this world space
				ns := get_nest_scale(nests);
				//ENTRANCE_CLIP_SIZE :: 20.;
				size := scalar_to_window(ENTRANCE_CLIP_SIZE) * ns;
				
				if nests == 0 
				{
					x0 : s32 = cast(s32)(pos_in_window.x-size);
					y0 : s32 = cast(s32)(pos_in_window.y-size);
					x1 : s32 = cast(s32)(pos_in_window.x+size);
					y1 : s32 = cast(s32)(pos_in_window.y+size);
					set_scissor(x0,y0,x1,y1);
				}

				// render the nested world
				origin := pos_in_window;
				origin.x -= window_width/2.;
				origin.y -= window_height/2.;
				world_render(a.child_world, nests+1, origin);
				
				color := get_nest_color(a.world.depth);
				thickness := scalar_to_window(8.) * ns;
				draw_box(.{pos_in_window.x, pos_in_window.y, size*2, size*2}, color, thickness);

				if nests == 0 {
					clear_scissor();
				}
			}
			*/
			
		}

		case .WorldExit; {
			a.flags |= .Pickupable | .BlockWarping;
			a.body.type = .Dynamic;
			a.body.size = .{8,8};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.world.focus = a;
			a.world.focus_default = a;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				print("% interacted with %\n", interactor.type, a.type);
				world_exit(interactor);
			}
		}

		case .Key; {
			a.flags |= .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{8,8};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
		}

		//@CLEAN
		//case .Tile; #through;
		//case .Tile_Red; { a.sprite.layer = -100;}
	}

	if a.proc_begin a.proc_begin(a);

	return a;
}

destroy :: (a : *Actor) {
	deinit_actor(a);
	a.world = null;
	a.child_world = null;

	a.proc_begin = null;
	a.proc_tick = null;
	a.proc_render = null;

	a.proc_on_interact = null;
	a.proc_on_dropped = null;
	a.proc_on_pickup = null;
	a.proc_onoverlap_interact = null;
	a.proc_onlifetime_expired = null;

	a.position = .{0,0};
	a.relative_position = .{0,0};
	a.prev_position = .{0,0};
	a.direction = .{0,0};
	a.velocity = .{0,0};

	collider_reset(*a.body);
	collider_reset(*a.interact_collider);

	a.held_item = null;
	a.parent = null;

	//if a.children.data != null @CLEAN
	array_reset_keeping_memory(*a.children);

	//@TODO marker logic
	//if a.marker {
	//	destroy(a.marker);
	//	a.marker = null;
	//}

	//@TODO is this a way to reinitialize the entire Actor?
	//a = Actor.{};
}


get_actor_tid :: (type : ActorType) -> TextureID {
	if type== {
		case .Hero; 			return TextureID.Hero;
		case .Tile;				return TextureID.Tile_01;
		case .Tile_Red;			return TextureID.Tile_Magma;
		case .Marker; 			return TextureID.Marker;
		case .WorldEntrance; 	return TextureID.Entrance;
		case .WorldExit; 		return TextureID.Exit;
		case .Key; 				return TextureID.ManaGem;
	}
	assert(false, "%", type);
	return .COUNT;
}

get_actor_sprite :: (type : ActorType) -> *Sprite {
	tid := get_actor_tid(type);
	return get_sprite(tid);
}

attach :: (parent : *Actor, child : *Actor, offset := Vector2.{0,0}, keep_body_enabled := false) {
	child.parent = parent;
	child.relative_position = offset;
	child.body.enabled = keep_body_enabled;
	array_add(*parent.children, child);
}

detach :: (child : *Actor) {
	assert(child != null);
	assert(child.parent != null);
	assert(child.parent.children.count > 0);

	child.position -= child.relative_position;
	child.relative_position = .{0,0};
	array_unordered_remove_by_value(*child.parent.children, child);
	child.parent = null;
}

is_holding_item :: (actor : *Actor) -> bool {
	return actor.held_item != null;
}

item_pickup :: (item : *Actor, owner : *Actor) {
	assert(item != null);
	assert(owner != null);

	if is_holding_item(owner)
		item_drop(owner);

	assert(owner.held_item == null);
	owner.held_item = item;
	attach(owner, item, .{0,20});

	if item.proc_on_pickup 
		item.proc_on_pickup(item);

	sfx := play_sound(.PickupStart);
	if sfx {
		sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
		sfx.rate_scale = random_get_within_range(0.7, 0.8); 
	}
	
}

hero_throw_strength := 375.;

item_drop :: (owner : *Actor) {
	assert(owner != null);

	if !is_holding_item(owner) return;

	item := owner.held_item;
	if item.proc_on_dropped 
		item.proc_on_dropped(item);

	// throw if moving
	//@TODO prob a more clever math to find if we're moving
	if length_squared(owner.position - owner.prev_position) > 0 {
		item.velocity = owner.direction * hero_throw_strength;

		sfx := play_sound(.PickupThrow);
		if sfx {
			sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
			sfx.rate_scale = random_get_within_range(0.7, 0.8); 
		}
	}
	else
	{
		sfx := play_sound(.PickupDrop);
		if sfx {
			sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
			sfx.rate_scale = random_get_within_range(0.6, 0.7); 
		}
	}

	detach(item);
	item.body.enabled = true;
	owner.held_item = null;
}

interact :: (a : *Actor, interactor : *Actor) {
	assert(a != null);
	assert(interactor != null);
	if a.proc_on_interact 
		a.proc_on_interact(a, interactor);
}

#load "engine.jai";
