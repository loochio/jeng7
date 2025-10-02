// assets.jai - Game F | 13 Sept 2026


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
