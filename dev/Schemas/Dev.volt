option clientOutput = "../Network/Client.luau"
option serverOutput = "../Network/Server.luau"
option runtime = "ReplicatedStorage.Packages.Volt"
option scope = Dev

-- The dev game's own traffic: the test elevator's button and the telemetry the live gates need from clients
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
