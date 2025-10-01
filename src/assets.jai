// assets.jai - Game F | 13 Sept 2026


// ~~~~~~~ Colors ~~~~~~~ 
//https://lospec.com/palette-list/cc-29
G_BLACK 		:: Vector4.{0.129, 0.129, 0.137, 1};
G_WHITE			:: Vector4.{0.949, 0.941, 0.898, 1};
G_GREY 			:: Vector4.{0.722, 0.71, 0.725, 1};
G_GREY2 		:: Vector4.{0.525, 0.506, 0.533, 1};
G_GREY3 		:: Vector4.{0.392, 0.388, 0.396, 1};
G_GREY3b	 	:: Vector4.{0.373, 0.333, 0.416, 1};
G_GREY4 		:: Vector4.{0.271, 0.267, 0.31, 1};
G_PURPLE	 	:: Vector4.{0.416, 0.325, 0.431, 1};
G_PURPLE2	 	:: Vector4.{0.294, 0.255, 0.345, 1};
G_PURPLE3 		:: Vector4.{0.208, 0.169, 0.259, 1};
G_BLUE	 		:: Vector4.{0.294, 0.502, 0.792, 1};
G_BLUE2 		:: Vector4.{0.263, 0.263, 0.416, 1};
G_BLUE3 		:: Vector4.{0.227, 0.22, 0.345, 1};
G_TEAL 			:: Vector4.{0.408, 0.761, 0.827, 1};
G_TEAL2 		:: Vector4.{0.337, 0.482, 0.475, 1};
G_GREEN 		:: Vector4.{0.635, 0.863, 0.78, 1};
G_GREEN2 		:: Vector4.{0.761, 0.827, 0.408, 1};
G_GREEN3 		:: Vector4.{0.541, 0.69, 0.376, 1};
G_GREEN4 		:: Vector4.{0.306, 0.345, 0.29, 1};
G_YELLOW 		:: Vector4.{0.929, 0.882, 0.62, 1};
G_YELLOW2 		:: Vector4.{0.482, 0.447, 0.263, 1};
G_YELLOW3 		:: Vector4.{0.698, 0.706, 0.494, 1};
G_ORANGE 		:: Vector4.{0.827, 0.627, 0.408, 1};
G_ORANGE2 		:: Vector4.{0.655, 0.482, 0.357, 1};
G_ORANGE3 		:: Vector4.{0.898, 0.808, 0.706, 1};
G_RED 			:: Vector4.{0.706, 0.322, 0.322, 1};
G_RED2	 		:: Vector4.{0.502, 0.286, 0.227, 1};
G_RED3 			:: Vector4.{0.929, 0.784, 0.769, 1};
G_PINK	 		:: Vector4.{0.812, 0.541, 0.796, 1};


//@TODO can probably roll this into a static array
draw_pallet :: () {
	d :: (index : s64, color : Vector4) {
		size := Vector2.{16,16};
		x := size.x * index + size.x;
		draw_square(.{x, size.y/2}, size, color);
	}
	d(0, G_BLACK);
	d(1, G_WHITE);
	d(2, G_GREY);
	d(3, G_GREY2);
	d(4, G_GREY3);
	d(5, G_GREY3b);
	d(6, G_GREY4);

	d(7, G_PURPLE);
	d(8, G_PURPLE2);
	d(9, G_PURPLE3);
	d(10, G_BLUE);
	d(11, G_BLUE2);
	d(12, G_BLUE3);

	d(13, G_TEAL);
	d(14, G_TEAL2);
	d(15, G_GREEN);
	d(16, G_GREEN2);
	d(17, G_GREEN3);
	d(18, G_YELLOW);
	d(19, G_YELLOW2);
	d(20, G_YELLOW3);
	d(21, G_ORANGE);
	d(22, G_ORANGE2);
	d(23, G_ORANGE3);
	d(24, G_RED);
	d(25, G_RED2);
	d(26, G_RED3);
	d(27, G_PINK);
}


// ~~~~~~~~~~~ sprites / textures ~~~~~~~~~~~ 

TextureID :: enum s64 {
	Hero;
	HeroRed;

	Entrance;
	Exit;
	ExitOutline;

	ButtonA;
	ButtonPickupA;
	LockA;
	LockBig;
	TimerResetA;


	Bug;
	Corpse;
	Bomb;
	Stone;
	StoneDust;
	Obsidian;
	Bush;
	ManaGem; //@TODO remove or reuse
	Marker;
	Pebble;

	Tile_01;
	Tile_Magma;

	DropZone;

	Sign;

	COUNT;
}

init_textures :: () {
	load :: (_id : TextureID, _name : string) {
		textures[_id] = .{ id=xx _id, name=_name };
		textures[_id].loaded = load_texture(_name, *textures[_id].texture);
		assert(textures[_id].loaded);
	}

	load(.Hero, 	"hero3/hero3.png");
	load(.HeroRed, 	"hero_red/hero_red.png");
	load(.Entrance, "entrance/entrance.png");
	load(.Exit, 	"exit/exit.png");
	load(.ExitOutline, 	"outline/outline.png");

	load(.ButtonA, 	"button_a/button_a.png");
	load(.ButtonPickupA, "button_pickup_a/button_pickup_a.png");
	load(.LockA, 	"lock_a/lock_a.png");
	load(.LockBig, 	"lock_big_a/lock_big_a.png");
	load(.TimerResetA, 	"timer_reset/timer_reset.png");

	load(.Bug, 		"bug/bug.png");
	load(.Corpse, 	"corpse/corpse.png");
	load(.Bomb, 	"bomb/bomb.png");
	load(.Stone, 	"stone/stone.png");
	load(.StoneDust, 	"stone_dust/stone_dust.png");
	load(.Obsidian, 	"obsidian/obsidian.png");
	load(.Bush, 	"bush/bush.png");
	load(.ManaGem, 	"managem/managem.png");
	load(.Marker, 	"marker/marker.png");
	load(.Pebble, 	"pebble/pebble.png");

	load(.Tile_01, 		"tile_block/tile_block.png");
	//load(.Tile_01, 		"tile_water_01.png");
	load(.Tile_Magma, 	"tile_magma/tile_magma.png");

	load(.DropZone, 	"dropzone/dropzone2.png");

	load(.Sign, 	"sign/sign.png");
}

textures : [TextureID.COUNT] _OLD_TextureAsset;
//TEXTURE_COUNT :: #run enum_highest_value(TextureID); 

get_texture :: (id : TextureID) -> *_OLD_TextureAsset{
	return *textures[id];
}


sprites : [TextureID.COUNT] Sprite;

init_sprites :: () {
	for sprites {
		sprites[it_index] = init_sprite(.Corpse);
	}

	sprites[TextureID.Hero] 	= init_sprite(.Hero, frames=2, play_length=1);
	sprites[TextureID.HeroRed] 	= init_sprite(.HeroRed, frames=2, play_length=1);

	sprites[TextureID.Entrance] = init_sprite(.Entrance);
	sprites[TextureID.Exit] 	= init_sprite(.Exit, frames=4, play_length=1);
	sprites[TextureID.ExitOutline] 	= init_sprite(.Exit, layer=-1);

	sprites[TextureID.ButtonA] 	= init_sprite(.ButtonA, frames=2, layer=-50);
	sprites[TextureID.ButtonPickupA] = init_sprite(.ButtonPickupA, frames=2);
	sprites[TextureID.LockA] 	= init_sprite(.LockA, frames=2, layer=-50);
	sprites[TextureID.LockBig] 	= init_sprite(.LockBig, frames=4, layer=-50, frame_size=.{64,64});
	sprites[TextureID.TimerResetA] = init_sprite(.TimerResetA, frames=2, layer=-100);


	sprites[TextureID.DropZone] = init_sprite(.DropZone, layer=-100);


	sprites[TextureID.Sign] = init_sprite(.Sign);


	sprites[TextureID.Bug] 		= init_sprite(.Bug, frames=4, play_length=0.25);
	sprites[TextureID.Corpse] 	= init_sprite(.Corpse);
	sprites[TextureID.Bomb] 	= init_sprite(.Bomb);
	sprites[TextureID.Stone] 	= init_sprite(.Stone);
	sprites[TextureID.StoneDust] = init_sprite(.StoneDust);
	sprites[TextureID.Obsidian] = init_sprite(.Obsidian);
	sprites[TextureID.Bush] 	= init_sprite(.Bush);
	sprites[TextureID.ManaGem] 	= init_sprite(.ManaGem, frames=4, play_length=.25);
	sprites[TextureID.Marker] 	= init_sprite(.Marker, frames=3, play_length=0.5, layer=200);
	sprites[TextureID.Pebble] 	= init_sprite(.Pebble);

	sprites[TextureID.Tile_01] 	= init_sprite(.Tile_01, layer=-100);
	sprites[TextureID.Tile_Magma] = init_sprite(.Tile_Magma, frames=4, play_length=1, layer=-100);
}

get_sprite :: (tid : TextureID) -> *Sprite {
	return *sprites[tid];
}


// ~~~~~~~~~~~ sfx ~~~~~~~~~~~ 


Sfx_ID :: enum s64 {
	Pause;
	RoundBegin;
	RoundComplete;
	Death;
	Hit;
	PickupStart;
	PickupThrow;
	PickupDrop;
	Warp;

	COUNT;
}

init_sound :: () {
	load :: (_id : Sfx_ID, _name : string) {
		sfx_assets[_id] = .{ id=xx _id, name=_name};
		sfx_assets[_id].data = load_sound(_name);
    	assert(sfx_assets[_id].data.loaded, "Sound failed to load: %", _name);
	}

	sound_player_init(.{update_from_a_thread = true});

	load(.Pause, 			"e16_Text_1.wav");
	load(.RoundBegin, 		"e16_Fruit_collect_1.wav");
	load(.RoundComplete, 	"e16_Big_Egg_collect_1.wav");
	load(.Death, 			"e16_Boss_hit_1.wav");
	load(.Hit, 				"e16_Hit_damage_1.wav");
	load(.PickupStart, 		"e16_Blow_2.wav");
	load(.PickupThrow, 		"e16_Jump_1.wav");
	load(.PickupDrop, 		"e16_Jump_1.wav");
	load(.Warp, 			"e16_Bubble_heavy_1.wav");
}

sfx_assets : [Sfx_ID.COUNT] SfxAsset; 

//@TODO probably merge this API with engine.play_sound()
play_sound :: (id : Sfx_ID, vol_min := 1., vol_max := 1., pitch_min := 1., pitch_max := 1.) -> *Sound_Stream {
	sfx := play_sound(*sfx_assets[id].data);
    if sfx {
    	sfx.user_volume_scale = random_get_within_range(vol_min, vol_max);
		sfx.rate_scale = random_get_within_range(pitch_min, pitch_max); 
    }
    return sfx;
}

// ~~~~~~~~~~~ vfx ~~~~~~~~~~~ 


EmitterType :: enum u32 {
	Generic;
	Explosion;
}

//@TODO need to account for worlds
spawn :: (emitter_type : EmitterType, pos := Vector2.{0,0}) -> *Particle_Emitter{

	ENABLED :: false;
	if !ENABLED return null;

	emitter := New(Particle_Emitter);
    using emitter;
    position = pos;

    if emitter_type == {
    	case .Generic; {
    		particles_per_second = 10;
    		velocity = Vector2.{0,100};
    		theta0 = TAU * 0.6;
		    theta1 = TAU * 0.9;
		    drag0 = 0.9;
		    drag1 = 0.97;

		    size0 = 0.001;
		    size1 = 0.03;

		    color0 = G_BLUE;
		    color1 = G_GREEN;

		    lifetime0 = 0.1;
		    lifetime1 = 0.25;
		    emitter_lifetime = 1;

		    fadeout_period = 0.12;
    	}

    	case .Explosion; {
    		particles_per_second = 10;
    		velocity = Vector2.{0,100};
    		theta0 = TAU * 0.6;
		    theta1 = TAU * 0.9;
		    drag0 = 0.9;
		    drag1 = 0.97;

		    size0 = 0.04;
		    size1 = 0.06;

		    color0 = G_RED;
		    color1 = G_BLACK;

		    lifetime0 = 0.1;
		    lifetime1 = 0.2;
		    fadeout_period = 0.12;

		    emitter_lifetime = 1;
    	}
    }
    
    array_add(*live_emitters, emitter);
    return emitter;
}

