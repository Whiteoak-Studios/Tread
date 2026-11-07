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

event shot {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (sequence: u16, target: u16?),
}

-- A report Tread's server raised about a player, which the dev server forwards to them for the exploit kit's panel
event report {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (kind: string(1..16), detail: string(0..64), dropped: u32),
}
