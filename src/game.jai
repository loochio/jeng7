/* Game F prototype - 13 Sept 2025

Idea: Recusive level warping
Inspirations: Coccoon | Patrick's Parabox | Inception | Antichamber | Sokaban heros (thekla)
	Talos Principle

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

startup_level_name :: "level_01";

game_paused := false;
game_over := false;
input_up := false;
input_down := false;
input_right := false;
input_left := false;

debug_colliders := false;

game_init :: () {
	print("~~ Game Init ~~ \n");
	register_cmd("game_restart", (args: .. Any) { game_restart(); });
	register_cmd("colliders", (args: .. Any) { debug_colliders = !debug_colliders; });
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

	w := world_init(startup_level_name);
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
	// keeping our active world ticked at depth=0
	for worlds {
		if !is_valid(*it) continue;
		if it.parent == null world_tick(*it, dt, -active_world.depth);
	}
}

toggle_pause :: () {
	game_paused = !game_paused;
	pause_physics = game_paused;
	play_sound(.Pause);
}


// ~~~ physics simulation ~~~
PHYSICS_ITERATIONS :: 1;
PHYSICS_SLEEP_THRESHOLD :: 0.0001;
PARTITION_CELL_SIZE :: 75.; // world units, needs to be large enough to cover a collider size
PARTITION_RANGE :: 1;

pause_physics := false;

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

game_render :: (dt : float) {
	{ // Parent World
		pos := Vector2.{window_width/2., window_height/2.};
		size := Vector2.{xx window_width, xx window_height};
		if active_world.parent == null {
			draw_square(pos, size, G_BLACK);
		}
		else {
			nests := -1.;
			//n := -1;
			//nests := ifx enter then n-active_world.transition_progress else n+active_world.transition_progress;
			clip := BoxFloat.{pos.x, pos.y, size.x, size.y};
			enter := active_world.transition_enter;
			world_render(active_world.parent, nests, clip, pos, false);
		}
	}
	
	{ // Active World, recursive rendering
		ACTIVE_WORLD_CLIP_SIZE :: 440.;
		clip_size_x := scalar_to_window(ACTIVE_WORLD_CLIP_SIZE) * 1.25;
		clip_size_y := scalar_to_window(ACTIVE_WORLD_CLIP_SIZE);
		sizex := clip_size_x;
		sizey := clip_size_y;

		// only scale the exit (@TODO for now)
		if active_world.transition_world != null && !active_world.transition_enter {
			assert(active_world.transition_progress >= 0);
			sc := SUBCLIP_SIZE_DEFAULT;
			dt := active_world.transition_progress;
			sizex = lerp(clip_size_x, sc, dt);
			sizey = lerp(clip_size_y, sc, dt);
		}

		clip := BoxFloat.{window_width/2., window_height/2., sizex, sizey};
		//clip := BoxFloat.{window_width/2., window_height/2., xx window_width, xx window_height};

		pos_in_window := Vector2.{0,0};
		world_render(active_world, 0, clip, pos_in_window);
	}
	
	//@TODO UI Layout rendering

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

	if debug_colliders {
		for *a : active_world.actors {
			if !is_valid(a) continue;

			p := vec_world_to_window(a.position, a.world);
			draw_collider(p, *a.body);
		}
	}
}

// ~~~ Worlds ~~~
World :: struct {
	using level : Level;
	flags : WorldFlags;
	depth := 0.; // nested level, float due to transition progress
	age := 0.; // relative age, factoring in time dilation
	parent : *World;

	transition_time := 0.;
	transition_progress := 0.; //[0-1]
	transition_enter := true;
	transition_actor : *Actor;
	transition_world : *World;

	actors : [MAX_ACTORS_PER_WORLD] Actor;
	actors_head := 0;
	actors_tail := 0;

	hero_spawn_index := 0;
	spawn_position : Vector2;
	hero : *Actor; //@TODO remove, looks like we only use this for Markers
	
	camera : Camera;
	focus : *Actor;
	focus_default : *Actor;
	background_fill := G_WHITE;
}

WorldFlags :: enum_flags u8 {
	Initialized :: 1;
}

MAX_WORLDS :: 8;
worlds : [MAX_WORLDS] World;
MAX_ACTORS_PER_WORLD :: 4096;

active_world : *World;
//game_mouse_pos_world : Vector2; @TODO not used currently

world_init :: (level_name : string, depth := 0.) -> *World {
	w : *World;
	for * worlds {
		if is_valid(it) continue;

		worlds[it_index] = .{};
		w = it;
		w.flags |= .Initialized;
		w.depth = depth;
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
vec_world_to_window :: (world_pos : Vector2, world : *World, nests := 0.) -> Vector2 {
	result := world_pos - world.camera.position;
	scale := get_window_aspect_scale();
	scale *= get_nest_scale(nests);
	result.x *= scale;
	result.y *= scale;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

world_enter_begin :: (a : *Actor, world : *World) {
	assert(a.type == .Hero);
	a.world.transition_time = WORLD_TRANSITION_TIME;
	a.world.transition_actor = a;
	a.world.transition_world = world;
	a.world.transition_enter = true;

	//@TODO need to consider how pausing world ticks effects other nested worlds
	//CLEAN exit world?
	//world.transition_time = WORLD_TRANSITION_TIME;

	sfx := play_sound(.Warp);
	//if sfx  sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
}

world_enter_end :: (world : *World) {
	assert(world.transition_actor != null);
	assert(world.transition_world != null);
	assert(world.transition_enter);
	world_enter(world.transition_actor, world.transition_world);
	world.transition_actor = null;
	world.transition_world = null;
}

world_enter :: (a : *Actor, world : *World) {
	// warp to the pos of target world's exit
	pos := Vector2.{};
	for world.actors { //@OPTIMIZE iterate on world.head/tail
		if !is_valid(*it) continue;

		if it.type == .WorldExit {
			pos = it.position;
			break;
		}
	}
	world_warp(a, world, pos);
}

world_exit_begin :: (a : *Actor) {
	a.world.transition_time = WORLD_TRANSITION_TIME;
	a.world.transition_actor = a;
	a.world.transition_enter = false;
	a.world.transition_world = a.world.parent;
	assert(a.world.parent != null);
}

world_exit_end :: (world : *World) {
	assert(world.transition_actor != null);
	assert(world.transition_world != null);
	assert(!world.transition_enter);
	world_exit(world.transition_actor);
	world.transition_actor = null;
	world.transition_world = null;
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

	sfx := play_sound(.Warp);
	if sfx {
		//sfx.user_volume_scale = random_get_within_range(0.15, 0.2);
		sfx.rate_scale = .7; 
	}
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

	//@TODO generic proc in the Actor
	if new_actor.type == {
		case .Hero; {
			world.focus = new_actor;
			world.hero = new_actor;
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

//@TODO is there a way we could schedule an arbitrary tick func? like a Task (struct)
world_tick :: (using world : *World, dt : float, nests := 0.) {
	assert(is_valid(world));

	// Time dilation, time moves faster in nested worlds (think Inception)
	pure_dt := dt;
	nest_time := get_nest_time(nests);
	dt *= 1/nest_time;
	age += dt;

    // cam lerp 
    camera.zoom = get_nest_scale(nests);
    if focus != null {
    	fp := focus.position;
    	camera.position = fp;
    	/* @TODO disabled lerp, maybe make this a flag on camera
		dist := distance(camera.position, fp);
		if dist > 0.1 {
		    camera.position = lerp(camera.position, fp, dt);
		}
		else {
			camera.position = fp;
		}*/
    }
	else {
		camera.position.x = 0;
		camera.position.y = 0;
	}
	
	// World transitions
	//@TODO this only works for entrace, need to do somethign for exit
	if transition_time > 0 {
		transition_time -= dt;
		transition_progress = 1. - (transition_time / WORLD_TRANSITION_TIME);

		if transition_time <= 0 {
			assert(transition_progress >= 1., "%", transition_progress);
			transition_time = 0;
			transition_progress = 0.;

			//@TODO generalize to world_transition_end
			if transition_enter {
				world_enter_end(world);
			}
			else {
				world_exit_end(world);
			}
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

WORLD_NESTED_SCALE :: 0.5;
WORLD_NESTED_SCALE_VEC :: Vector2.{WORLD_NESTED_SCALE, WORLD_NESTED_SCALE};
SUBCLIP_SIZE_DEFAULT :: 200.;
SUBCLIP_SIZE_MAX :: 2000; //@TODO should be max(window_width, window_height);
SUBCLIP_OUTLINE_THICKNESS :: 8.;
WORLD_NESTED_TIME :: 0.25;
WORLD_TRANSITION_TIME :: 0.25; 
//WORLD_TRANSITION_TIME :: 2.; //@CLEAN

get_nest_scale :: (nests := 0.) -> float {
	return pow(WORLD_NESTED_SCALE, nests);
}

get_nest_scale_vec :: (nests := 0.) -> Vector2 {
	scale := get_nest_scale(nests);
	return Vector2.{scale, scale};
}

get_nest_time :: (nests := 0.) -> float {
	return pow(WORLD_NESTED_TIME, nests);
}

get_nest_color :: (nests : float) -> Vector4 {
	return lerp(BLUE, RED, nests / 3.);
}

world_render :: (using world : *World, nests : float, window_clip : BoxFloat, pos_in_window : Vector2, should_render_subworlds := true) {
	assert(is_valid(world), "%", world.name);

	{ // scissor clip for this world, cleared before next recursive call
		//@TODO change window_clip to an AABB
		x0 := cast(s32)(window_clip.x - window_clip.w/2.);
		y0 := cast(s32)(window_clip.y - window_clip.h/2.);
		x1 := cast(s32)(window_clip.x + window_clip.w/2.);
		y1 := cast(s32)(window_clip.y + window_clip.h/2.);
		set_scissor(x0,y0,x1,y1);
	}

	{ // background fill
		color := world.background_fill * get_nest_color(world.depth);
		draw_square(.{window_clip.x, window_clip.y}, .{window_clip.w, window_clip.h}, color);
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

	// nest scaling, accounting for tranisitons
	enter := world.transition_enter;
	n := ifx enter then nests - world.transition_progress else nests + world.transition_progress;
	nscale := get_nest_scale_vec(n);

	// final window scale
	winscale := get_window_aspect_scale();
	scale := winscale * nscale;

	// sprite rendering
	for a : sorted_actors {
		assert(is_valid(a));

		// inlining vec_world_to_window() for clarity
		pos := a.position - world.camera.position;
		pos *= scale;
		pos.x += window_width/2.;
		pos.y += window_height/2.;
		pos += pos_in_window; // recursively add our pos

		render_sprite(*a.sprite, pos, nscale);
	}

	// draw window_clip border 
	{
		outline := window_clip;
		thickness := scalar_to_window(SUBCLIP_OUTLINE_THICKNESS) * nscale.x;
		color := world.background_fill * get_nest_color(world.depth) * .75;
		color.w = 1;
		draw_box(outline, color, thickness);

		// time marker, white box on outline
		TIME_PER_CYCLE :: 30.;
		progress := fmod_cycling(world.age,TIME_PER_CYCLE) / TIME_PER_CYCLE;
		p := get_box_percent_pos(*outline, progress);
		size := scalar_to_window(8) * nscale.x;
		draw_circle(p, size, color=G_WHITE);
	}

	// clear the scissor now so we can set a new one in our recursive render_entrance() call
	clear_scissor();

	// recursive actor rendering, only for render_entrance(..) for now.
	//@OPTIMIZE we should simplify this to just find WorldEntrance and handle subworld_render(..) here
	if should_render_subworlds {
		for a : sorted_actors {
			if a.proc_render {
				pos := vec_world_to_window(a.position, world, n);
				pos += pos_in_window; // recursively add our pos
				a.proc_render(a, n, window_clip, pos);
			}
		}
	}

	//@OPTIMIZE move this to an array_reset_safe(..) type of func
	if sorted_actors.data != null
		array_reset(*sorted_actors);
}

subworld_render := (a : *Actor, nests : float, window_clip : BoxFloat, pos_in_window : Vector2) {
	// find new clipping box, subdividing our current window_clip
	nscale := get_nest_scale(nests);
	subclip : BoxFloat;
	subclip.x = pos_in_window.x;
	subclip.y = pos_in_window.y;

	// only widen this subclip for the target transition entrance
	//@TODO some duplicated code to improve
	subclip_size := SUBCLIP_SIZE_DEFAULT;

	if a.world.transition_world != null {
		if a.world.transition_world == a.child_world {
			//enter tranistion
			subclip_max := max(window_width*1.25, window_height*1.25);
			subclip_size = lerp(SUBCLIP_SIZE_DEFAULT, subclip_max, a.world.transition_progress);
		}
		//else if a.world.transition_world == a.world.parent {
		//	subclip_size := SUBCLIP_SIZE_DEFAULT;
		//}
	}
	
	box_size := subclip_size * nscale;
	subclip.w = box_size;
	subclip.h = box_size;

	overlapping, intersection := get_box_intersection(window_clip, subclip);

	if overlapping {
		//scuffed eps check
		assert(intersection.w <= subclip.w+1. && intersection.h <= subclip.h+1., 
			"nests=% | win=% | sub=% | intersection=%", nests, window_clip, subclip, intersection);

		origin := pos_in_window;
		origin.x -= window_width/2.;
		origin.y -= window_height/2.;
		world_render(a.child_world, nests+1, intersection, origin);

		//@TODO render this an outline sprite, needs to respect the world_render(..) scissor
	}
}

// get the position around the edge of the box given a percent
// start in bottom left, progress clockwise
get_box_percent_pos :: (box : *BoxFloat, percent : float) -> Vector2{
	percent = clamp(percent, 0., 1.);
	result : Vector2;
	x := box.x;
	y := box.y;
	w := box.w;
	h := box.h;

	if percent >= 0 && percent < .25 {
		result.x = x-w/2.;
		result.y = lerp(y-h/2., y+h/2., percent*4);
	}
	else if percent >= .25 && percent < .5 {
		result.x = lerp(x-w/2., x+w/2., (percent-.25)*4);
		result.y = y+h/2.;
	}
	else if percent >= .5 && percent < .75 {
		result.x = x+w/2.;
		result.y = lerp(y+h/2., y-h/2., (percent-.5)*4);
	}
	else { 
		result.x = lerp(x+w/2., x-w/2., (percent-.75)*4);
		result.y = y-h/2.;
	}
	return result;
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
	assert(level.name.count == 0, "%", level.name);
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

		print("\tload warp: % name=% pos=%\n", w, w.level_name, w.position);
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

// ~~~ Actors ~~~

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

	speed := Vector2.{1,1}; // speed of the character added per frame (typically Heros)
	interact_collider : Collider;
	proc_onoverlap_interact : ActorProc_Overlap;

	lifetime := -1.;
	lifetime_dt := 0.;
	proc_onlifetime_expired : ActorProc;

	held_item : *Actor;

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
ActorProc_Render :: #type (actor : *Actor, nests : float, clip : BoxFloat, pos_in_window : Vector2);
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

		world.actors[world.actors_tail-1] = Actor.{};
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
	
	if a.type == {
		case .Hero; {
			a.speed = .{50,50};
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn | .Hero;
			a.body.collides_with = .Wall | .Pawn;
			a.interact_collider.type = .Trigger;
			a.interact_collider.size = .{36,36};
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
			a.body.type = .Kinematic;
			a.body.size = .{SUBCLIP_SIZE_DEFAULT/4.,SUBCLIP_SIZE_DEFAULT/4.};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_render = subworld_render; 

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				if interactor.type == {
					case .Hero; world_enter_begin(interactor, a.child_world);
					case; 		world_enter(interactor, a.child_world);
				}
			}
		}

		case .WorldExit; {
			a.flags |= .Pickupable | .BlockWarping;
			a.body.type = .Kinematic;
			a.body.size = .{8,8};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.world.focus = a;
			a.world.focus_default = a;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				if interactor.type == {
					case .Hero; world_exit_begin(interactor);
					case; 		world_exit(interactor);
				}
			}
		}

		case .Key; {
			a.flags |= .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{8,8};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
		}
	}

	if a.proc_begin a.proc_begin(a);

	return a;
}

destroy :: (a : *Actor) {
	deinit_actor(a);
	collider_reset(*a.body);
	collider_reset(*a.interact_collider);
	array_reset_keeping_memory(*a.children);
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
	offset := Vector2.{0., owner.body.size.y + item.body.size.y};
	attach(owner, item, offset);

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
