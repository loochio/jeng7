/* Game F prototype - 13 Sept 2025

Idea: Recusive level warping
Inspirations: Coccoon | Patrick's Parabox | Inception | Antichamber | Sokaban heros (thekla)
	Talos Principle | Zelda: LTTP | Animal Well


26 Sept 2025
Confirmed POC prototype v0.1
Some fun ideas in a tightly designed package, plenty to explore.
Need more robust engine tech.
	- Asset Manager (textures, sprites, sfx, fonts)
	- UI, layouts (vertical, horizontal, grid)
	- square colliders, improve physics jank
		HOWEVER, physics jank was fun in initial v0.1 playtests
	- shaders

Gameplay Engine Tech Ideas
	- fluid sims
	- lighting / lasers
	- gravity (maybe tie into the fluid sims, ex black hole sucking up smoke/water)
	- audio visualization, maybe more than just visual?

Need to do an Aethetic prototype.


27 Sept 2025 from crispy_penguin
TODO: Fix later


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

level_root : string; 	// root level to load from
level_start : string; 	// level the player will begin in

game_paused := false;

game_init :: () {
	print("~~ Game Init ~~ \n");
	register_cheats();
	game_begin();
}

game_deinit :: () {
	game_end();
	print("~~ Game Deinit ~~\n");
}

game_begin :: () {
	print("~~ Game Begin ~~\n");
	game_paused = false;

	//@TODO could move to generic engine.init(), reset flow would change a little for hot reload
	set_configs("game");
	assert(is_valid(level_root));
	assert(is_valid(level_start));

	// initialize from the root world
	actor_guid = 0;
	root_world := world_init(level_root);
	assert(root_world != null);
	for * worlds {
		if !is_valid(it) continue;
		world_begin(it);

		if it.name == level_start {
			active_world = it;
		}
	}
	assert(active_world != null);

	// Possess our first available option
	for * active_world.actors {
		if !is_valid(it) continue;

		if it.flags & .CanPossess {
			possess(it);
			break;
		}
	}

	//play_sound(.RoundBegin);
	print("\tInitial world activation: %\n", active_world.name);
}

game_end :: () {
	print("~~ Game End ~~\n");

	for worlds {
		if !is_valid(*it) continue;
		world_deinit(*it);
	}
	active_world = null;

	active_sign.enabled = false;
}

game_restart :: () {
	print("Game Restart\n");
	game_end();
	game_begin();
}

game_tick :: (dt : float) {
	if is_input_pressed(.TAB) toggle_pause();
	if is_input_pressed(.ENTER) game_restart();

	#if DEVELOPER {
		if is_input_pressed(.F5) {
			set_plugin("editor");
			return;
		}
	}

	if game_paused  return;

	if active_sign.enabled {
		if is_input_pressed(81) sign_hide(); //Q to hide
		return;
	}

	//@TODO clearing InteractTarget at the begining of the frame because we don't have
	// an on_overlap_end type of callback yet
	for * active_world.actors {
		if !is_valid(it) continue;
		it.flags &= ~.InteractTarget;
	}

	// Tick root worlds (ones without a parent)
	// we start from the negative active world's depth, keeping our active world ticked at depth=0
	world_tick_pure(active_world, dt);
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
PHYSICS_SLEEP_THRESHOLD :: 0.0001;
PARTITION_CELL_SIZE :: 100.; // world units, needs to be large enough to cover a collider size
PARTITION_RANGE :: 1;

pause_physics := false;
enable_collisions := true;
debug_colliders := false;


//@TODO could move to engine.jai
is_in_partition_range :: (a0 : *Actor, a1 : *Actor) -> bool {
	return abs(a0.partition_cell_x - a1.partition_cell_x) <= PARTITION_RANGE 
		&& abs(a0.partition_cell_y - a1.partition_cell_y) <= PARTITION_RANGE;
}

//@TODO could move to engine.jai
get_partition_pos :: (cell_x : s64, cell_y : s64) -> Vector2 {
	return .{ 
		PARTITION_CELL_SIZE * (xx cell_x + 0.5), 
		PARTITION_CELL_SIZE * (xx cell_y + 0.5)
	};
}

//@TODO could move to engine.jai
get_partition_index_from_world_pos :: (pos : float) -> s64 {
	return xx (pos / PARTITION_CELL_SIZE);
}

physics_tick :: (using world : *World, dt : float) {
	if pause_physics return;

	// update pos
	for a : actors {
	//for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
	//	if !is_valid(a) continue;

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
	for a : actors {
	//for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
	//	if !is_valid(a) continue;

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
	if !enable_collisions return;

	for a : actors {
	//for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
	//	if !is_valid(a) continue;

		if !a.body.enabled continue;
		if a.body.asleep continue;
		if a.body.type != .Dynamic continue; 

		for b : actors {
		//for j : actors_head..actors_tail { @CLEAN 
		//	b := *actors[j];
		//	if !is_valid(b) continue;

			if a == b continue;
			if !is_in_partition_range(a,b) continue;

			// a is overlapping b, resolve collision, move a out of b
			//@OPTIMIZE tons of duplicated math, refactor for ez speed gains
			// There's a lot that can be refactored down in to is_overlap(..)
			if is_overlap(a.position, *a.body, b.position, *b.body) {
				apos := a.position;
				bpos := b.position;
				dv0 := bpos-apos;
				dir := normalize(dv0);
				dist := distance(apos, bpos);

				//@OPTIMIZE move this into is_overlap(..)
				if b.body.shape== {
					case .Circle; {
						diff := a.body.size.x + b.body.size.x - dist; //overlap depth
						dv := dir*diff;

						if b.body.type == {
							case .Dynamic; {
								a.position -= dv/2.;
								b.position += dv/2.;
							}
							case .Static; #through;
							case .Kinematic; {
								a.position -= dv;
							}
						}
					}
					case .Box; {
						assert(b.body.type != .Dynamic); //@TODO side stepping this case for now
						
						//if apos.x > bpos.x-b.body.size.x/2. && apos.x < bpos.x+b.body.size.x/2. {
						//	dx := (bpos.x-apos.x) - (a.body.size.x + b.body.size.x/2.);
						//	if dx < 0 {
						//		a.position.x += dx; 
						//	}
						//} 
						//
						//if apos.y > bpos.y-b.body.size.y/2. && apos.y < bpos.y+b.body.size.y/2. {
						//	dy := (bpos.y-apos.y) - (a.body.size.y + b.body.size.y/2.);
						//	if dy < 0 {
						//		a.position.y += dy; 
						//	}
						//}
						

						//edge_x := clamp(apos.x, bpos.x-b.body.size.x/2., bpos.x+b.body.size.x/2.);
						//edge_y := clamp(apos.y, bpos.y-b.body.size.y/2., bpos.y+b.body.size.y/2.);
						//dx := apos.x - edge_x; //@CLEAN
						

						//dy := apos.y - edge_y;
						//if apos.x > bpos.x-b.body.size.x/2. {
						//	a.position.x = bpos.x-b.body.size.x/2. - a.body.size.x;
						//}
						//if apos.x < bpos.x+b.body.size.x/2. {
						//	a.position.x = bpos.x-b.body.size.x/2. - a.body.size.x;
						//}

						//@TODO temp
						diff := a.body.size.x + b.body.size.x - dist; //overlap depth
						dv := dir*diff;
						if b.body.type == {
							//case .Dynamic; {
							//	a.position -= dv/2.;
							//	b.position += dv/2.;
							//}
							case .Static; #through;
							case .Kinematic; {
								a.position -= dv/2.;
							}
						}
						
					}
				}

				if a.proc_onhit a.proc_onhit(a,b);
				if b.proc_onhit b.proc_onhit(b,a);

				//@TODO handle first overlap event
				//if a.body.flags & .Overlapping == 0 {
				//	//print("first overlap A\n");
				//	a.body.flags |= .Overlapping;
				//}
				//if b.body.flags & .Overlapping == 0{
				//	print("first overlap B\n");
				//	b.body.flags |= .Overlapping;
				//}
			}
		}
	}
}

game_render :: (dt : float) {
	{ // Parent World
		pos := window_center;
		size := window_size;
		if active_world.parent == null {
			draw_square(pos, size, G_BLACK);
		}
		else {
			nests := -1.;
			//n := -1;
			//nests := ifx enter then n-active_world.transition_progress else n+active_world.transition_progress;
			clip := Box.{pos.x, pos.y, size.x, size.y};
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

		clip := Box.{window_center.x, window_center.y, sizex, sizey};
		pos_in_window := Vector2.{0,0};
		world_render(active_world, 0, clip, pos_in_window);
	}
	

	// clock ui rendering
	offset := 100.;
	offset_index := 0;
	for *w : worlds {
		if !is_valid(w) continue;

		for a : w.actors {
			//@CLEAN
		//for i : w.actors_head..w.actors_tail {
		//	a := *w.actors[i];
		//	if !is_valid(a) continue;

			// only render active timers
			if !has_flag(a, .UnlocksA) continue;
			if a.lifetime <= 0. continue;

			o := offset_index * offset;
			pos := Vector2.{(xx window_width)-100., (xx window_height)-(100.+o)};
			render_clock(a, 0, Box.{}, pos);
			offset_index += 1;

			seconds := a.lifetime - a.lifetime_dt;
			//@TODO multiply by current depth
			seconds *= 1/get_nest_time(a.depth);
			{
				text := tprint("% (s)", formatFloat(seconds, trailing_width=1));
				width := prepare_text(hud_font, text);
				pos.y -= 56.;
		    	draw_prepared_text(hud_font, xx(pos.x-width/2.), xx pos.y, G_WHITE);
			}
			{
				text := tprint("depth=%",cast(s64)a.depth);
				width := prepare_text(hud_font, text);
				pos.y -= hud_font.character_height;
		    	draw_prepared_text(hud_font, xx(pos.x-width/2.), xx pos.y, G_WHITE);
			}
		}
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

	draw_text(9, "World: %", active_world.name);

	if game_paused {
		text := "PAUSED";
		text_width := prepare_text(hud_font, text);
		text_x := (window_width - text_width) / 2;
	    text_y := window_height * 0.95;
	    draw_prepared_text(hud_font, text_x, xx text_y, G_BLACK);
	}

	if active_sign.enabled {
		sign_render(dt);
	}

	if debug_colliders {
		for *a : active_world.actors {
			if !is_valid(a) continue;

			// main body
			p := vec_world_to_window(a.position, a.world);
			size := Vector2.{scalar_to_window(a.body.size.x), scalar_to_window(a.body.size.y)};
			draw_collider(*a.body, p, size);

			// interact collider
			sizei := Vector2.{scalar_to_window(a.interact_collider.size.x), scalar_to_window(a.interact_collider.size.y)};
			draw_collider(*a.interact_collider, p, sizei);
		}
	}
}

// ~~~ Worlds ~~~
World :: struct {
	using level : Level;
	flags : WorldFlags;
	timeflags : WorldTimeFlags;
	depth := 0.; // nested level, float due to transition progress
	age := 0.; // relative age, factoring in time dilation
	parent : *World;

	transition_time := 0.;
	transition_progress := 0.; //[0-1]
	transition_enter := true; //@TODO move to WorldFlags
	transition_actor : *Actor;
	transition_world : *World;

	actors : Pool(Actor, MAX_ACTORS_PER_WORLD);

	//@CLEAN
	//actors : [MAX_ACTORS_PER_WORLD] Actor;
	//actors_head := 0;
	//actors_tail := 0;
	
	camera : Camera;
	focus : *Actor;
	focus_default : *Actor;
	background_fill := G_WHITE;
}

WorldFlags :: enum_flags u8 {
	Initialized 	:: 1;
}

WorldTimeFlags :: enum_flags u8 {
	TimeFlipped 	:: 1;
	TimeInfinite 	:: 1<<1;
}


MAX_WORLDS :: 32; // fun fact: 128 worlds adds 1.2 sec to our total compile time (compared to 8 worlds)
worlds : [MAX_WORLDS] World;
MAX_ACTORS_PER_WORLD :: 4096;
actor_guid := 0;
active_world : *World;

world_init :: (level_name : string, depth := 0.) -> *World {
	w : *World;
	for * worlds {
		if is_valid(it) continue;

		worlds[it_index] = .{};
		w = it;
		w.flags |= .Initialized;
		//w.flags |= .TimeFlipped; make time faster
		w.depth = depth;
		break;
	}
	assert(w != null);

	level_load(level_name, *w.level);
	print("World initialize: % [%]\n", w.name, w);

	// warps, linking worlds
	for w.spawners {
		if it.type != .WorldEntrance continue;

		level_name := it.data;
		assert(is_valid(level_name), "%", level_name);
		if exists(level_name) continue;

		print("recursive world init: %\n", level_name);
		world_init(level_name, depth+1);
	}
	return w;
}


world_deinit :: (using world : *World) {
	level_reset(*level);
	flags = 0;

	for * actors actor_free(it);
}

world_begin :: (world : *World) {
	assert(is_valid(world));
	
	// initial actor spawning
	for * world.spawners spawn(world, it);
}

get_world :: (name : string) -> *World{
	for * worlds {
		if !is_valid(it) continue;
		if it.name == name  return it;
	}
	assert(false, "failed to find world [%]\n", name);
	return null;
}

is_valid ::(world : *World) -> bool {
	return world.flags & .Initialized != 0;
}

exists :: (world_name : string) -> bool {
	for * worlds {
		if !is_valid(it) continue;
		if it.name == world_name  return true;
	}
	return false;
}

// Convert a vector in the given world space
// replacing coords_world_to_window() to accommadate new world system
vec_world_to_window :: (world_pos : Vector2, world : *World, nests := 0.) -> Vector2 {
	result := world_pos - world.camera.position;
	scale := get_window_aspect_scale();
	scale *= get_nest_scale(nests);
	result.x *= scale * forced_window_scale_x;
	result.y *= scale * forced_window_scale_y;
	result.x += window_width/2.;
	result.y += window_height/2.;
	return result;
}

set_active_world :: (actor : *Actor) {
	assert(has_flag(actor, .Possessed));
	active_world = actor.world;
	active_world.focus = actor;
}

// begin a transition to the specified world, pop to the actor.world.parent if no world provideds
world_transition_begin :: (a : *Actor, world : *World = null) {
	enter := world != null;
	if !enter && a.world.parent == null {
		//@TODO probably should setup a default parent world we always warp to
		print("ERROR No parent world found\n");
		return;
	}

	// enter world immediately if not possessed
	if !has_flag(a, .Possessed) {
		if enter {
			world_enter(a, world);
		}
		else {
			world_exit(a);
		}
		return;
	}

	a.world.transition_enter = enter;
	a.world.transition_time = WORLD_TRANSITION_TIME;
	a.world.transition_actor = a;
	a.world.transition_world = ifx enter then world else a.world.parent;
	assert(a.world.transition_world != null);

	play_sound(.Warp);
}

world_transition_end :: (using world : *World) {
	assert(transition_progress >= 1., "%", transition_progress);
	assert(transition_actor != null);
	assert(transition_world != null);

	transition_time = 0;
	transition_progress = 0.;

	if transition_enter {
		world_enter(transition_actor, transition_world);
	}
	else {
		world_exit(transition_actor);
	}
	transition_actor = null;
	transition_world = null;
}

world_enter :: (a : *Actor, world : *World) {
	print("world enter | type=%\n", a.type);
	// warp to the pos of target world's exit
	pos := Vector2.{};
	for world.actors {
		//@CLEAN
	//for world.actors { //@OPTIMIZE iterate on world.head/tail
	//	if !is_valid(*it) continue;

		if it.type == .WorldExit {
			pos = it.position;
			print("found exit position%\n", pos);
			break;
		}
	}

	new_actor := move_actor_to_world(a, world, pos);
	if new_actor && has_flag(new_actor, .Possessed){
		set_active_world(new_actor);
	}
}

world_exit :: (a : *Actor) {
	print("world EXIT | type=%\n", a.type);
	assert(a != null);
	assert(a.world.parent != null);

	// set the focus of this exiting world
	if has_flag(a, .Possessed) {
		for * a.world.actors { //@OPTIMIZE iterate on world.head/tail
			if !is_valid(it) continue;

			if it.type == .WorldExit {
				a.world.focus = it;
				break;
			}
		}
	}

	// warp to the parent entrance position
	pos := Vector2.{};
	for a.world.parent.actors { 
		//if !is_valid(it) continue; @CLEAN

		if it.type == .WorldEntrance && a.world == it.child_world {
			pos = it.position;
			break;
		}
	}

	new_actor := move_actor_to_world(a, a.world.parent, pos);

	if new_actor && has_flag(new_actor, .Possessed){
		set_active_world(new_actor);
		play_sound(.Warp, pitch_min=.7, pitch_max=.7);
	}
}

move_actor_to_world :: (actor : *Actor, world : *World, pos := Vector2.{}) -> *Actor{
	// block trying to reenter the same world
	if actor.world == world {
		print("reentering the same world | aid=% | type=%\n", actor.id, actor.type);
		actor.position = pos;
		return actor;
	}

	// force blocked items to drop before we start moving memory between worlds
	item := actor.held_item;
	if item != null && (item.flags & .BlockWarping != 0) {
		print("force dropping item=% | flags=%\n", item.type, item.flags);
		item_drop(actor);
		item = null;
	}

	assert(actor.world != world);
	new_actor := actor_alloc(world, actor.type);
	memcpy(new_actor, actor, size_of(Actor));
 	actor_free(actor);

	// we need to reset the world bc it gets overwritten with memcpy()
	new_actor.world = world;
	new_actor.position = pos;
	new_actor.held_item = null;

	if item != null {
		i := move_actor_to_world(item, world);
		item_pickup(i, new_actor);
	}

	//@TODO generic proc in the Actor
	//new_actor.proc_on_world_move(new_actor);
	if new_actor.type == {
		case .WorldEntrance; {
			// update the linked worlds along with their depth (level of nesting)
			new_actor.child_world.parent = world;
			new_actor.child_world.depth = world.depth+1;

			//@DESIGN opportunity here for a different type of WorldEntrance
			// one that doesn't change its child_world.parent
			// this can create a one way exit, always exiting in the same place
		}
	}

	// update world conditions, wipe any time flags
	//@OPTIMIZE potentially sloppy, does this need to be more precise
	//@OPTIMIZE2 yes, this needs to be more precise for TimeInfinite (for now)
	for *w : worlds {
		if !is_valid(w) continue;
		w.timeflags &= ~.TimeInfinite;
	}
	
	return new_actor;
}

is_world_transitioning :: (world : *World) -> bool {
	return world.transition_time > 0 ;
}

// ticking the active world, not subject to nested time
world_tick_pure :: (using world : *World, dt : float) {
	// World transitions
	if is_world_transitioning(world) {
		transition_time -= dt;
		transition_progress = 1. - (transition_time / WORLD_TRANSITION_TIME);

		if transition_time <= 0 world_transition_end(world);
		return;
	}

	// actors
	for a : actors {
    //for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
    //	if !is_valid(a) continue;

    	if a.proc_tick_pure a.proc_tick_pure(a, dt);
    }

	physics_tick(world, dt);
}

//@TODO is there a way we could schedule an arbitrary tick func? like a Task (struct)
world_tick :: (using world : *World, dt : float, nests := 0.) {
	assert(is_valid(world));

	if is_world_transitioning(world) return;

	// Time dilation, time moves faster in nested worlds (think Inception)
	pure_dt := dt;
	nest_time := get_nest_time(nests);

	// time calculations based on flags
	if world.timeflags & .TimeInfinite {
		dt = 0.;
	}
	else if world.timeflags & .TimeFlipped {
		dt = dt/nest_time;
	}
	else {
		dt = dt*nest_time;
	}
	age += dt;

    // cam lerp 
    camera.zoom = get_nest_scale(nests);
    if focus != null {
    	fp := focus.position;
    	camera.position = fp;
    }
	else {
		camera.position.x = 0;
		camera.position.y = 0;
	}
	
	// actor ticks
	for a : actors {
    //for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
    //	if !is_valid(a) continue;

    	if (a.proc_tick) a.proc_tick(a, dt);

    	if a.body.type != .Static {
 	   		a.sprite.flipped = a.direction.x < 0;
    	}
		
		sprite_tick(*a.sprite, dt);
    	
    	a.depth = nests;
    	a.lifetime_dt += dt;
		if a.lifetime > 0 && a.lifetime_dt >= a.lifetime {
			if a.proc_onlifetime_expired
				a.proc_onlifetime_expired(a);

			if a.flags & .DestroyAfterLifetime {
				print("LIFETIME EXPIRATION type=%\n", a.type);
				actor_free(a);
			}
		}

		for child : a.children {
			child.position = a.position;
			child.position += child.relative_position;
		}
    }

    // recursive world ticks, tick child worlds
    if nests > WORLD_TICK_NEST_MAX {
    	world.timeflags |= .TimeInfinite;
    	return;
    }

    for actors {
   // for actors { @CLEAN
   // 	if !is_valid(*it) continue;

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
WORLD_NESTED_TIME :: 0.15;
WORLD_TIME_PER_CYCLE :: 10.; // for the revolving outline marker
WORLD_TRANSITION_TIME :: 0.25; 
WORLD_TICK_NEST_MAX :: 10.;
WORLD_RENDER_NEST_MAX :: 4.; // max num of nested subworlds to render



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
	if nests < 0 		return G_PURPLE;
	else if nests <= 0 	return G_BLUE;
	else if nests <= 1 	return G_GREEN3;
	else if nests <= 2 	return G_YELLOW;
	else if nests <= 3 	return G_ORANGE;
	else if nests <= 4 	return G_RED;
	else if nests <= 5 	return G_PURPLE;
	else				return G_WHITE;
}

get_world_color :: (world : *World) -> Vector4 {
	if world.timeflags & .TimeInfinite {
		return G_BLACK;
	}
	return get_nest_color(world.depth);
}

world_render :: (using world : *World, nests : float, window_clip : Box, pos_in_window : Vector2, should_render_subworlds := true) {
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
		color := world.background_fill * get_world_color(world);
		draw_square(.{window_clip.x, window_clip.y}, .{window_clip.w, window_clip.h}, color);
	}
	
	// sprite rendering, sorted by position.y
	sorted_actors : [..] *Actor;

	for a : actors {
	//for i : actors_head..actors_tail { @CLEAN
	//	a := *actors[i];
	//	if !is_valid(a) continue;
//
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

		if a.proc_render a.proc_render(a, n, window_clip, pos);
	}

	// draw window_clip border 
	{
		outline := window_clip;
		thickness := scalar_to_window(SUBCLIP_OUTLINE_THICKNESS) * nscale.x;
		color := world.background_fill * get_world_color(world) * .75;
		color.w = 1;
		draw_box(outline, color, thickness);

		// time marker, white box on outline
		draw_dot :: (outline : Box, world : *World, nests : float, nscale : Vector2, offset := 0.) {
			progress := fmod_cycling(world.age,WORLD_TIME_PER_CYCLE) / WORLD_TIME_PER_CYCLE;
			progress -= offset;
			p := get_box_percent_pos(*outline, progress);
			ofactor := pow(1-offset, 15.);
			size := scalar_to_window(8 * ofactor) * nscale.x;
			c := G_WHITE;
			c.w *= ofactor;
			if nests < 0 c.w *= 0.1;
			draw_circle(p, size, color=c);
		}
		trails :: 10;
		for 0..trails {
			draw_dot(outline, world, nests, nscale, 0.01*it);
		}
	}

	// clear the scissor now so we can set a new one in our recursive subworld_render() call
	clear_scissor();

	// recursive actor rendering, only for subworld_render(..) for now.
	//@OPTIMIZE we should simplify this to just find WorldEntrance and handle subworld_render(..) here
	if should_render_subworlds {
		for a : sorted_actors {
			if a.proc_render_subworld {
				pos := vec_world_to_window(a.position, world, n);
				pos += pos_in_window; // recursively add our pos
				a.proc_render_subworld(a, n, window_clip, pos);
			}
		}
	}

	// interaction ui
	for a : sorted_actors {
		if has_flag(a, .InteractTarget) {
			//@TODO duplicated with above sprite rendering, clean this up eventually
			pos := a.position - world.camera.position;
			pos *= scale;
			pos.x += window_width/2.;
			pos.y += window_height/2.;
			pos += pos_in_window; // recursively add our pos

			w := prepare_text(hud_font, "[Q]");
			offset := scalar_to_window(20.);
			posi := Vector2.{pos.x-w/2., pos.y+offset};
			draw_prepared_text(hud_font, xx posi.x, xx posi.y, G_BLACK);
		}
	}

	//@OPTIMIZE move this to an array_reset_safe(..) type of func
	if sorted_actors.data != null
		array_reset(*sorted_actors);
}

subworld_render := (a : *Actor, nests : float, window_clip : Box, pos_in_window : Vector2) {
	// find new clipping box, subdividing our current window_clip
	nscale := get_nest_scale(nests);
	subclip : Box;
	subclip.x = pos_in_window.x;
	subclip.y = pos_in_window.y;

	// only widen this subclip for the target transition entrance
	subclip_size := SUBCLIP_SIZE_DEFAULT;

	if a.world.transition_world != null &&  a.world.transition_world == a.child_world {
		subclip_max := max(window_width*1.25, window_height*1.25);
		subclip_size = lerp(SUBCLIP_SIZE_DEFAULT, subclip_max, a.world.transition_progress);
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

		if nests <= WORLD_RENDER_NEST_MAX {
			world_render(a.child_world, nests+1, intersection, origin);
		}
		else {
			draw_box(intersection, get_world_color(a.child_world));
		}
	}
}

// get the position around the edge of the box given a percent
// start in bottom left, progress clockwise
get_box_percent_pos :: (box : *Box, percent : float) -> Vector2{
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
}

ActorSpawner :: struct {
	type : ActorType; //@TODO could be generalized to s64, justifying the move to engine.jai
	position : Vector2;
	scale := Vector2.{1,1};
	data : string;
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
			spawner := cast(*u8)it;
			append(*builder, spawner, size_of(ActorSpawner));

			// extra spawner data
			len := cast(*u8)*it.data.count;
			append(*builder, len, size_of(s64));
			append(*builder, it.data);
		}
	}

	write_entire_file(path, *builder);
	reset(*builder);
	print("Saved %\n", path);
}

is_valid_level_name :: (name : string) -> bool {
	path := tprint("levels/%.level", name);
	return file_exists(path);
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
		spawner := ActorSpawner.{};
		consume_u8_and_length(*buffer, cast(*u8)*spawner, size_of(ActorSpawner));

		len := 0;
		consume_u8_and_length(*buffer, cast(*u8)*len, size_of(s64));
		spawner.data = alloc_string(len);
		consume_u8_and_length(*buffer, spawner.data.data, len);

		//@TODO need to figure out this enum validation
		if type_of(spawner.type) == ActorType {
			array_add(*level.spawners, spawner);
		}
		else{
			print("\tFailed to parse spawner: % in level=%\n", spawner.type, level.name);
		}

		{// Validation
			low, high := enum_range(ActorType);
			type : s64 = xx spawner.type;
			assert(type >= low, "%", type);
			assert(type <= high, "%", type);
		}
	}

	if name != level.name {
		print("\told name [%] detected on level=%, updating name\n", level.name, name);
		string_reset(*level.name);
		level.name = sprint(name);
	}

	print("LOADED: name=% | spawners=%\n", level.name, level.spawners.count);
	return true;
}

level_reset :: (level : *Level) {
	assert(is_valid(level));
	assert(level.name.count > 0);
	string_reset(*level.name);

	for * level.spawners {
		spawner_reset(it);
	}

	if level.spawners.data != null
		array_reset(*level.spawners);
}

spawner_reset :: (spawner : *ActorSpawner) {
	assert(spawner != null);
	string_reset(*spawner.data);
}

is_valid :: (level : *Level) -> bool {
	return level.name.count > 0;
}

// ~~~ Actors ~~~

Actor :: struct {
	id := 0;
	type := ActorType.EMPTY;
	flags : ActorFlags;
	world : *World;
	child_world : *World;
	payload : string;
	depth : float = 0.; // current depth this actor is ticking at

	proc_begin : ActorProc;
	proc_tick : ActorProc_Tick;
	proc_tick_pure : ActorProc_Tick;
	proc_render : ActorProc_Render;
	proc_render_subworld : ActorProc_Render;
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

	children : [..]*Actor;
	parent : *Actor;
	relative_position : Vector2;

	held_item : *Actor;
	weight : u8 = 0;
	strength : u8 = 0;
	counter := 0; // generic counter used for misc data

	link : s64 = 0; //@CLEAN old, remove
}

ActorType :: enum s64 #specified {
	EMPTY 		:: -1; // should never be serialized, using for world.actor mem

	Hero		:: 0;
	Marker		:: 1;
	Block 		:: 2;
	Tile_Red 	:: 3;
	WorldEntrance :: 4;
	WorldExit 	:: 5; // warps to the parent world

	//Hero :: 1000; //@TODO scuffed enum values for now
	HeroRed		:: 1001; 
	Kid			:: 1002; // gooblet

	Console 		:: 2000;
	ConsoleMovable 	:: 2001;

	WallLock 		:: 3000; // green lock A (circle)
	WallLockBig		:: 3001; // big lock (gooblet)

	DropZone 		:: 4000; // causes held items to drop
	TimerResetA 	:: 4001; // reset all A timers (green circle)

	Sign 			:: 10000;
}

ActorFlags :: enum_flags s64 {
	Initialized		:: 1;
	CanPossess 		:: 1 <<2;
	Possessed 		:: 1 <<3;
	BlockWarping	:: 1<<4; // VERY IMPORTANT for exits or else the game logically doesn't make sense
	DestroyAfterLifetime :: 1<<5;

	Pickupable		:: 1<<19;
	Interactable	:: 1<<20;
	BlockInteract	:: 1<<21;
	InteractTarget	:: 1<<22;

	LockA 			:: 1<<23;
	UnlocksA 		:: 1<<24;
	ResetsA 		:: 1<<25;

	LockBig 		:: 1<<26;
	UnlocksBig 		:: 1<<27;
}

has_flag :: (a: *Actor, flag : ActorFlags) -> bool {
	return a.flags & flag != 0;
}

get_actor_tid :: (type : ActorType) -> TextureID {
	if type== {
		case .Hero; 			return TextureID.Hero;
		case .HeroRed; 			return TextureID.HeroRed;
		case .Kid; 				return TextureID.Bug;

		case .Block;			return TextureID.Tile_01;

		case .Console; 			return TextureID.ButtonA;
		case .ConsoleMovable;	return TextureID.ButtonPickupA;
		case .WallLock; 		return TextureID.LockA;
		case .WallLockBig; 		return TextureID.LockBig;
		case .TimerResetA; 		return TextureID.TimerResetA;


		case .DropZone; 		return TextureID.DropZone;

		case .Sign; 			return TextureID.Sign;


		case .Tile_Red;			return TextureID.Tile_Magma;
		case .Marker; 			return TextureID.Marker;
		case .WorldEntrance; 	return TextureID.Entrance;
		case .WorldExit; 		return TextureID.Exit;
	}
	assert(false, "%", type);
	return .COUNT;
}

get_actor_sprite :: (type : ActorType) -> *Sprite {
	tid := get_actor_tid(type);
	return get_sprite(tid);
}


ActorProc :: #type (actor : *Actor);
ActorProc_Tick :: #type (actor : *Actor, dt : float);
ActorProc_Render :: #type (actor : *Actor, nests : float, clip : Box, pos_in_window : Vector2);
ActorProc_Overlap :: #type (a0 : *Actor, a1 : *Actor);

is_valid :: (actor : *Actor) -> bool{
	return actor.type != .EMPTY && actor.flags & .Initialized != 0;
}

is_valid_actor_spawner :: (type : ActorType) -> bool {
	if type== {
		case .EMPTY; return false;
		case .Marker; return false;
	}
	return true;
}

get_actor :: (aid : s64) -> *Actor {
	for worlds {
		for *a : it.actors {
			if !is_valid(a) continue;

			if a.id == aid return a;
		}
	}
	assert(false, "actor id not found = %", aid);
	return null;
}

actor_alloc :: (world : *World, type : ActorType) -> *Actor{
	actor := pool_alloc(*world.actors);
	actor.type = type;
	actor.flags |= .Initialized;
	actor_guid += 1;
	actor.id = actor_guid;
	actor.world = world;
	assert(is_valid(actor), "type=%", type);
	return actor;
} 

actor_free :: (a : *Actor) {
	string_reset(*a.payload);
	collider_reset(*a.body);
	collider_reset(*a.interact_collider);
	array_reset_keeping_memory(*a.children);

	pool_remove(*a.world.actors, a);
}

// hero configs
HERO_SPEED_DEFAULT 	:: Vector2.{50,50};
HERO_SPEED_FAST 	:: Vector2.{200,200};
hero_throw_strength := 375.;

spawn :: (world : *World, type : ActorType, pos := Vector2.{0,0}) -> *Actor{
	spawner := ActorSpawner.{type, pos, .{1,1}, ""};
	return spawn(world, *spawner);
}

spawn :: (world : *World, spawner : *ActorSpawner) -> *Actor{
	a := actor_alloc(world, spawner.type);
	assert(is_valid(a));
	a.sprite = get_actor_sprite(a.type);
	a.position = spawner.position;
	a.payload = sprint(spawner.data);
	
	if a.type == {
		case .Hero; #through;
		case .HeroRed;
		{
			a.flags |= .CanPossess | .Interactable | .Pickupable;
			a.speed = HERO_SPEED_DEFAULT;
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn | .Hero; //@TODO should only be one type
			a.body.collides_with = .Wall | .Pawn;
			a.interact_collider.type = .Trigger;
			a.interact_collider.size = .{36,36};
			a.interact_collider.is_a = .Pawn | .Hero;
			a.interact_collider.collides_with = .Pawn | .Hero;

			a.proc_tick_pure = player_tick_pure;

			// swap on interact
			a.proc_on_interact = (target : *Actor, interactor : *Actor) {
				assert(interactor.flags & .Possessed != 0, "%", interactor.type);
				assert(target.flags & .Possessed == 0, "%", target.type);
				possess(target, interactor);
			}
		}

		case .Kid; {
			a.flags |= .Pickupable;
			a.body.type = .Dynamic;
			a.body.size = .{12,12};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Wall | .Pawn;
		}

		case .WorldEntrance; {
			a.flags |= .Interactable | .Pickupable;
			a.body.type = .Kinematic;
			//a.body.size = .{SUBCLIP_SIZE_DEFAULT/4.,SUBCLIP_SIZE_DEFAULT/4.}; @CLEAN
			a.body.shape = .Box;
			a.body.size = .{64,64};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.weight = 1;

			// link this world to a child world
			a.child_world = get_world(spawner.data);

			// only set the parent on the first time, preventing broken exit chains
			if a.child_world.parent == null
				a.child_world.parent = a.world;

			a.proc_render_subworld = subworld_render; 

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				// set the exit parent to the world you're coming from
				a.child_world.parent = a.world;
				world_transition_begin(interactor, a.child_world);
			}

			//@DESIGN warp on collision, needs to work given that everything warps back right away
			//a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
			//	if a1.flags & .BlockWarping return;
			//
			//	world_enter_begin(a1, a0.child_world);
			//}
		}

		case .WorldExit; {
			a.flags |= .Interactable | .BlockWarping | .Pickupable;
			a.body.type = .Kinematic;
			a.body.size = .{16,16};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;
			a.weight = 1;
			a.world.focus = a;
			a.world.focus_default = a;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				world_transition_begin(interactor);
			}
		}

		case .Block; {
			a.body.type = .Static;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;
		}

		case .Console; {
			a.flags |= .Interactable | .UnlocksA;
			a.body.type = .Static;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;

			sprite_pause(*a.sprite);

			a.proc_render = render_clock;
			a.proc_on_interact = console_interact_a;
			a.proc_onlifetime_expired = (a : *Actor) {
				console_deinteract(a);
				play_sound(.Pause);
			}
		}

		case .ConsoleMovable; {
			a.flags |= .Interactable | .Pickupable | .UnlocksA;
			a.body.type = .Dynamic;
			a.body.size = .{16,16};
			a.body.is_a = .Pawn;
			a.body.collides_with = .Pawn | .Wall;

			sprite_pause(*a.sprite);

			a.proc_render = render_clock;
			a.proc_on_interact = console_interact_a;
			//@CLEAN a.proc_onlifetime_expired = console_deinteract;

			a.proc_onlifetime_expired = (a : *Actor) {
				console_deinteract(a);
				play_sound(.Pause);
			}
		}

		case .WallLock; {
			a.flags |= .LockA;
			a.body.type = .Static;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				sprite_step(*a.sprite);
				a.body.type = ifx a.body.type == .Inactive then .Static else .Inactive;
			}

			sprite_pause(*a.sprite);
		}

		case .DropZone; {
			a.body.type = .Trigger;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn;

			a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
				if is_holding_item(a1) {
					item_drop(a1);
					play_sound(.Death, vol_min=0.5, vol_max=0.6, pitch_min=0.95, pitch_max=1.1);
				}
			}
		}

		case .TimerResetA; {
			//@OPTIMIZE this whole actor is error prone, very fragile
			// There's (flag) LockA, which is required for the initial on_interact
			// on_interact gives (flag) ResetsA
			// on_hit resets active locks (.UnlocksA | .BlockInteract)
			// removes (flag) ResetsA

			a.flags |= .LockA; // needed to react to proc_on_interact
			a.body.type = .Trigger;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn;
			sprite_pause(*a.sprite);

			a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
				if !has_flag(a0, .ResetsA) return;

				//reset all A Timers (green circle)
				//@OPTIMIZE trigger this during an on_overlap_begin event
				for worlds {
					for a : it.actors {
						if a == a0 continue;
						if has_flag(a, .UnlocksA | .BlockInteract) {
							console_deinteract(a);
						}
					}
				}
				for worlds {
					for a : it.actors {
						if a.type == .TimerResetA {
							a.flags &= ~.ResetsA;
							sprite_reset(*a.sprite);
						}
					}
				}
				play_sound(.Pause);
			}

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				a.flags |= .ResetsA;
				sprite_step(*a.sprite);
			}
		}

		case .WallLockBig; {
			a.flags |= .LockBig;
			a.body.type = .Static;
			a.body.shape = .Box;
			a.body.size = .{64,64};
			a.body.is_a = .Wall;
			a.body.collides_with = .Pawn | .Wall;
			sprite_pause(*a.sprite);

			a.counter = 3;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				sprite_step(*a.sprite);
				a.body.type = ifx a.body.type == .Inactive then .Static else .Inactive;
			}

			a.proc_onhit = (a0 : *Actor, a1 : *Actor) {
				assert(a0.type == .WallLockBig);
				if a1.type == .Kid {
					a0.counter -= 1;
					actor_free(a1);
					sprite_step(*a0.sprite);

					if a0.counter <= 0 {
						print("!!! BIG UNLOCK !!!\n");
						a0.body.type = .Inactive;
						play_sound(.RoundComplete);
					}
					else {
						play_sound(.RoundBegin);
					}
				}
			}
		}

		case .Sign; {
			a.flags |= .Interactable;
			a.body.type = .Trigger;
			a.body.shape = .Box;
			a.body.size = .{32,32};
			a.body.is_a = .Wall;
			a.body.collides_with = .Hero;

			a.proc_on_interact = (a : *Actor, interactor : *Actor) {
				sign_show(a.payload);
			}
		}
	}

	if a.type == {
		case .HeroRed; {
			a.strength = 1;
		}
	}

	if a.proc_begin a.proc_begin(a);

	return a;
}

// Player takes control of this actor
possess :: (target : *Actor, current : * Actor = null) {
	assert(target.flags & .CanPossess != 0);
	assert(target.flags & .Possessed == 0);

	print("\n Possessed target=%\n", target.type);
	target.flags |= .Possessed;
	target.world.focus = target;

	if current {
		assert(current.flags & .CanPossess != 0);
		assert(current.flags & .Possessed != 0);
		assert(current.world == target.world);
		current.flags &= ~.Possessed;
		print("\n \tunpossessed old=%\n", current.type);
	}
}

player_tick_pure :: (a : *Actor, dt : float) {
	assert(has_flag(a, .CanPossess));

	// skip non-possessed heros
	if !has_flag(a, .Possessed) return;

	// movement
	input_up := is_input_down(87) || is_input_down(.ARROW_UP); //w
	input_down := is_input_down(83) || is_input_down(.ARROW_DOWN); //s
	input_left := is_input_down(65) || is_input_down(.ARROW_LEFT); //a
	input_right := is_input_down(68) || is_input_down(.ARROW_RIGHT); //d

	dv : Vector2;
    if input_up  dv.y += 1.;
    if input_down dv.y -= 1.;
    if input_right dv.x += 1.;
    if input_left dv.x -= 1.;

	a.position.x += dv.x * a.speed.x * dt;
	a.position.y += dv.y * a.speed.y * dt;

    // item pickups
	w := a.world;

    if is_input_pressed(69) { //E
    	if a.held_item {
    		item_drop(a);
    	}
    	else
    	{
    		for b : w.actors {
    		//for i : w.actors_head..w.actors_tail { @CLEAN
			//	b := *w.actors[i];
	    	//	if !is_valid(b) continue;
//
				//b := it;
	    		if a == b continue;
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
    interact_target : *Actor;

    // find a target
    for b : w.actors {
	//for i : w.actors_head..w.actors_tail {
	//	b := *w.actors[i];
	//	if !is_valid(b) continue;

		//b := it;
		if a == b continue;
		if b.flags & .Interactable == 0 continue;
		if b.flags & .BlockInteract != 0 continue;
		if !is_in_partition_range(a, b) continue;

		if is_overlap(a.position, *a.interact_collider, b.position, *b.body) {
			interact_target = b;
			interact_target.flags |= .InteractTarget;
			break;
		}
	}

	if is_input_pressed(81, true) && interact_target != null { //Q
		interact(interact_target, a);
	}
}

console_interact_a :: (a : *Actor, interactor : *Actor) {
	a.flags |= .BlockInteract;
	a.lifetime = 3.;
	a.lifetime_dt = 0.;

	// open first time
	assert(has_flag(a, .UnlocksA));
	for *w : worlds {
		if !is_valid(w) continue;
		for *target : w.actors {
			if !is_valid(target) continue;

			if has_flag(target, .LockA) interact(target, a);
		}
	}

	sprite_step(*a.sprite);
	play_sound(.RoundBegin);
}

console_deinteract :: (a : *Actor) {
	if a.lifetime < 0 {
		assert(!has_flag(a, .BlockInteract));
		return;
	}

	a.flags &= ~.BlockInteract;
	a.lifetime = -1.;
	sprite_step(*a.sprite);

	// open up the locks
	assert(has_flag(a, .UnlocksA));
	for *w : worlds {
		if !is_valid(w) continue;
		for *target : w.actors {
			if !is_valid(target) continue;

			if has_flag(target, .LockA) interact(target, a);
		}
	}
}

render_clock :: (a : *Actor, nests : float, clip : Box, pos_in_window : Vector2) {
	progress := ifx a.lifetime > 0 then  a.lifetime_dt / a.lifetime else 0.;

	// timer draw circle
	//@TODO this doesn't account correctly for subworld_rendering
	if progress > 0 {
		//pos := vec_world_to_window(a.position, a.world, nests); @CLEAN
		r := scalar_to_window(12) * get_nest_scale(nests);
		c := lerp(G_GREEN2, G_RED, progress); //@CLEAN
		//c := get_nest_color(nests); //@CLEAN
		draw_circle(pos_in_window, r*1.2, r*.75, G_BLACK);
		draw_circle(pos_in_window, r, 0, c, progress);
	}
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

can_pickup_item :: (item : *Actor, owner : *Actor) -> bool {
	return item.weight <= owner.strength;
}

item_pickup :: (item : *Actor, owner : *Actor) {
	assert(item != null);
	assert(owner != null);

	if !can_pickup_item(item, owner) {
		sfx := play_sound(.PickupStart, vol_min=0.15, vol_max=0.2, pitch_min=0.4, pitch_max=0.5);
		return;
	}

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
		play_sound(.PickupDrop, vol_min=0.15, vol_max=0.2, pitch_min=0.6, pitch_max=0.7);
	}

	detach(item);
	item.body.enabled = true;
	owner.held_item = null;
}

interact :: (target : *Actor, interactor : *Actor) {
	assert(target != null);
	assert(interactor != null);
	assert(target.flags & .BlockInteract == 0);
	
	if target.proc_on_interact 
		target.proc_on_interact(target, interactor);
}

Sign :: struct {
	enabled := false;
	type := SignType.Yellow;
	message : string;
}

SignType :: enum s64 {
	Yellow :: 1;
}

active_sign : Sign;

sign_show :: (message : string) {
	print("sign interact: message=%\n", message);
	active_sign.enabled = true;
	active_sign.message = message;
	play_sound(.Pause);
}

sign_hide :: () {
	print("sign hide\n");
	active_sign.enabled = false;
	play_sound(.Pause, pitch_min=0.85, pitch_max=0.85);
}

// draw a posted note with message text
sign_render :: (dt : float) {
	pos := Vector2.{window_width/2., window_height/2.};
	size_win := Vector2.{xx window_width, xx window_height};
	c := G_PURPLE3;
	c.w = 0.7;
	draw_square(pos, size_win, c);

	size := scalar_to_window(400.);
	draw_square(pos, .{size,size}, G_YELLOW3);

	size2 := scalar_to_window(300.);
	draw_square(pos, .{size2,size2}, G_YELLOW);

	// draw UI
	r := Rect.{pos.x-size2/2., pos.y-size2/2., size2, size2};
	theme : = hud_theme.label_theme;
	theme.alignment = .Center;
	{
		msgs := split(active_sign.message, "|"); //@FIXME leak?
		lh := r.h*.1;
		for msgs {
			i := it_index+1;
			r0 := Rect.{r.x,r.y+r.h-(lh*i), r.w, lh};
		    label(r0, it, *theme);
		}
	}
	{
		r0 := Rect.{r.x,r.y, r.w, r.h*.1};
	    label(r0, "[Q] Close", *theme);
	}
}

register_cheats :: () {
	//@DESIGN these terminal commands are meant to be found in game.
	// Knowledge based keys, "unlocks" when entered into the game for the first time
	// Store that unlock state in GameCareer save profile
	//@TODO terminal auto complete only shows commands you have unlocked
	register_cmd("reset", (args: .. Any) { game_restart(); });

	register_cmd("teser", (args: .. Any) { 
		// reset and reverse time
		game_restart(); 
		for * worlds {
			if !is_valid(it) continue;
			it.timeflags |= .TimeFlipped;
		}
	});

	register_cmd("goto", (args: .. Any) { 
		if args.count == 1 {
			arg := args[0];
			name := tprint("%", arg);

			if !exists(name) {
				print("goto failed, level does not exist: %\n", name);
				return;
			}

			for active_world.actors {
				if has_flag(it, .Possessed) {
					world := get_world(name);
					world_enter(it, world);
				}
			}
		}
	});

	/*
	register_cmd("rseet", (args: .. Any) { 
		// typo, deliberately fuck up the screen bc why not?
		//@TODO the engine level mod needs to be undone after the next restart
		// Probably stuff this into a GameState struct, ensure we wipe it every restart
		game_restart(); 
		//forced_window_scale_y *= -2.; 
		forced_window_scale_y *= -1.; //@TODO needs to be undone
		//forced_window_scale_x *= -1.; //@TODO needs to be undone
		print("force_window_scale_y = %\n", forced_window_scale_y);

		//@DESIGN with the way this fucks up the sprite translations,
		// I can see a fun idea where the sprite moves out of the way, and we can see behind it.
		// Put a secret behind there?
	});
	*/

	/* @TODO maybe reimplement, active_world.hero was removed
	register_cmd("fast", (args: .. Any) { 
		// make hero fast
		//@DESIGN a more fun idea would decrease the hero tick dt
		active_world.hero.speed = HERO_SPEED_FAST;
	});

	register_cmd("slow", (args: .. Any) { 
		// make hero slow, default
		active_world.hero.speed = HERO_SPEED_DEFAULT;
	});
	*/
	
	#if DEVELOPER {
		register_cmd("colliders", (args: .. Any) { debug_colliders = !debug_colliders; });
		register_cmd("gas", (args: .. Any) {  enable_collisions = !enable_collisions; });
	}	
}

// game.ini settings
//@TODO move to engine.jai, generalize this to be a .ini for the plugin
set_configs :: (filename : string) {
	path := tprint("config/%.ini", filename);
	buffer, success := read_entire_file(path);
	defer(free(buffer));

	if !success {
		print("Failed to load config: %\n", path);
		return;
	}

	lines := split(buffer, "\n");
	for lines {
		line := trim(it);

		if line.count == 0 continue;
		if begins_with_nocase(line, "#") continue;

		statement := split(line, "=");

		if statement.count != 2 {
			print("\t[ERROR] malformed line: %\n", line);
			continue;
		}

		key := statement[0];
		value := trim(statement[1]);
		if key== {
			case "root";  {
				string_reset(*level_root);
				level_root = sprint(value);
			}
			case "start"; {
				string_reset(*level_start);
				level_start = sprint(value);
			}
		}
	}

	print("~~~ Loaded configs: % ~~~\n", path);
	print("\troot: %\n", level_root);
	print("\tstart: %\n", level_start);
}

#load "engine.jai";
