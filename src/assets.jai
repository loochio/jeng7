// assets.jai - Game F | 13 Sept 2026


// ~~~~~~~~~~~ sprites / textures ~~~~~~~~~~~ 

/*
//@CLEAN remove
TextureID :: enum s64 {
	_DONE_Hero;
	_DONE_HeroRed;
	_DONE_Entrance;
	_DONE_Exit;
	ButtonA;
	ButtonPickupA;
	LockA;
	LockBig;
	TimerResetA;
	_DONE_Bug;
	Tile_01;
	DropZone;
	Sign;


	//@CLEAN
	//ExitOutline;
	//Corpse;
	//Bomb;
	//Stone;
	//StoneDust;
	//Obsidian;
	//Bush;
	//ManaGem; //@TODO remove or reuse
	//Marker;
	//Pebble;
//
	//Tile_Magma;

	COUNT;
}
*/
/*
_OLD_init_textures :: () {
	load :: (_id : TextureID, _name : string) {
		_OLD_textures[_id] = .{ id=xx _id, name=_name };
		_OLD_textures[_id].loaded = load_raw_texture(_name, *_OLD_textures[_id].texture);
		assert(_OLD_textures[_id].loaded);
	}

	//@CLEAN migration targets
	load(._DONE_Hero, 	"hero3/hero3.png");
	load(._DONE_HeroRed, 	"hero_red/hero_red.png");
	load(._DONE_Entrance, "entrance/entrance.png");
	load(._DONE_Exit, 	"exit/exit.png");
	load(._DONE_Bug, 		"bug/bug.png");
	load(.ButtonA, 	"button_a/button_a.png");
	load(.ButtonPickupA, "button_pickup_a/button_pickup_a.png");
	load(.LockA, 	"lock_a/lock_a.png");
	load(.LockBig, 	"lock_big_a/lock_big_a.png");
	load(.TimerResetA, 	"timer_reset/timer_reset.png");
	load(.Tile_01, 		"tile_block/tile_block.png");
	load(.DropZone, 	"dropzone/dropzone2.png");
	load(.Sign, 	"sign/sign.png");


	//@CLEAN old
	//load(.ExitOutline, 	"outline/outline.png");
//
	//load(.Corpse, 	"corpse/corpse.png");
	//load(.Bomb, 	"bomb/bomb.png");
	//load(.Stone, 	"stone/stone.png");
	//load(.StoneDust, 	"stone_dust/stone_dust.png");
	//load(.Obsidian, 	"obsidian/obsidian.png");
	//load(.Bush, 	"bush/bush.png");
	//load(.ManaGem, 	"managem/managem.png");
	//load(.Marker, 	"marker/marker.png");
	//load(.Pebble, 	"pebble/pebble.png");
//
	////load(.Tile_01, 		"tile_water_01.png");
	//load(.Tile_Magma, 	"tile_magma/tile_magma.png");

}
*/

/*
_OLD_textures : [TextureID.COUNT] _OLD_TextureAsset;

_OLD_get_texture :: (id : TextureID) -> *_OLD_TextureAsset{
	return *_OLD_textures[id];
}

_OLD_sprites : [TextureID.COUNT] Sprite;


_OLD_init_sprites :: () {
	for _OLD_sprites {
		_OLD_sprites[it_index] = _OLD_init_sprite(.Tile_01);
	}

	//@CLEAN migration targets
	_OLD_sprites[TextureID._DONE_Hero] 	= _OLD_init_sprite(._DONE_Hero, frames=2, play_length=1);
	_OLD_sprites[TextureID._DONE_HeroRed] 	= _OLD_init_sprite(._DONE_HeroRed, frames=2, play_length=1);
	_OLD_sprites[TextureID._DONE_Entrance] = _OLD_init_sprite(._DONE_Entrance);
	_OLD_sprites[TextureID._DONE_Exit] 	= _OLD_init_sprite(._DONE_Exit, frames=4, play_length=1);
	_OLD_sprites[TextureID._DONE_Bug] 		= _OLD_init_sprite(._DONE_Bug, frames=4, play_length=0.25);
	
	_OLD_sprites[TextureID.ButtonA] 	= _OLD_init_sprite(.ButtonA, frames=2);
	_OLD_sprites[TextureID.ButtonPickupA] = _OLD_init_sprite(.ButtonPickupA, frames=2);
	_OLD_sprites[TextureID.LockA] 	= _OLD_init_sprite(.LockA, frames=2);
	_OLD_sprites[TextureID.LockBig] 	= _OLD_init_sprite(.LockBig, frames=4, frame_size=.{64,64});
	_OLD_sprites[TextureID.TimerResetA] = _OLD_init_sprite(.TimerResetA, frames=2);
	_OLD_sprites[TextureID.DropZone] = _OLD_init_sprite(.DropZone);
	_OLD_sprites[TextureID.Sign] = _OLD_init_sprite(.Sign);
	_OLD_sprites[TextureID.Tile_01] 	= _OLD_init_sprite(.Tile_01);


	//@CLEAN OLD
	//_OLD_sprites[TextureID.ExitOutline] 	= _OLD_init_sprite(.Exit);
//
	//_OLD_sprites[TextureID.Corpse] 	= _OLD_init_sprite(.Corpse);
	//_OLD_sprites[TextureID.Bomb] 	= _OLD_init_sprite(.Bomb);
	//_OLD_sprites[TextureID.Stone] 	= _OLD_init_sprite(.Stone);
	//_OLD_sprites[TextureID.StoneDust] = _OLD_init_sprite(.StoneDust);
	//_OLD_sprites[TextureID.Obsidian] = _OLD_init_sprite(.Obsidian);
	//_OLD_sprites[TextureID.Bush] 	= _OLD_init_sprite(.Bush);
	//_OLD_sprites[TextureID.ManaGem] 	= _OLD_init_sprite(.ManaGem, frames=4, play_length=.25);
	//_OLD_sprites[TextureID.Marker] 	= _OLD_init_sprite(.Marker, frames=3, play_length=0.5);
	//_OLD_sprites[TextureID.Pebble] 	= _OLD_init_sprite(.Pebble);
	//_OLD_sprites[TextureID.Tile_Magma] = _OLD_init_sprite(.Tile_Magma, frames=4, play_length=1);
}

_OLD_get_sprite :: (tid : TextureID) -> *Sprite {
	return *_OLD_sprites[tid];
}
*/


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

_OLD_init_sound :: () {
	load :: (_id : Sfx_ID, _name : string) {
		sfx_assets[_id] = .{ id=xx _id, name=_name};
		sfx_assets[_id].data = load_sound(_name);
    	assert(sfx_assets[_id].data.loaded, "Sound failed to load: %", _name);
	}

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
