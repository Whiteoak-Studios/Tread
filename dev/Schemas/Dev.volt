option clientOutput = "../Network/Client.luau"
option serverOutput = "../Network/Server.luau"
option runtime = "ReplicatedStorage.Packages.Volt"
option scope = Dev

-- The dev game's own traffic: the test elevator's button, the telemetry the live gates need from clients, and the
-- reports the exploit kit's panel shows
event press {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (platform: u8(1..127)),
}

event corrected {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (size: f32, flagged: boolean),
}

-- What a shooter's own view of one of its fixture shots struck: the sequence's low 6 bits are the shooter's per-run
-- counter, and the target is the slot alone, since the client's Tread.Slot carries no generation, nil for a miss
event shot {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (sequence: u16, target: u16?),
}

-- Tells the dev client to fire G7's fixture shots from the hotbar slot named, until a 0 stops it
event shoot {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (slot: u8(0..6)),
}

-- A report Tread's server raised about a player, which the dev server forwards to them for the exploit kit's panel
event report {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (kind: string(1..16), detail: string(0..64), dropped: u32),
}

-- One part of a clip the Playback scenario recorded: its index and its list's total, and whether its list is the
-- withheld frames or the keyframe and the observed frames. Its bytes stay well under Volt's 8,192 B maxPacket
event clip {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (withheld: boolean, index: u8(1..255), total: u8(1..255), bytes: buffer(0..4096)),
}

-- The dev client's word that it played the clip, with the clip time it ended at and whether its stop key ended it
event played {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (time: f32, stopped: boolean),
}
