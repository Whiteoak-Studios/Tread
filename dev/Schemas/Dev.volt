option clientOutput = "../Network/Client.luau"
option serverOutput = "../Network/Server.luau"
option runtime = "ReplicatedStorage.Packages.Volt"
option scope = Dev

-- The dev game's own traffic: the test elevator's button, the telemetry the live gates need from clients, the
-- reports the exploit kit's panel shows, the live runs' trigger and reports, and the bot panel's asks and numbers
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

-- A client's ask that the server start the live run of that name
event run {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (name: string(1..32)),
}

-- What the server says of a live run a client asked for: refused with the reason, running with the run's name, each
-- piece of its report in order, then passed or failed with the name. Of the Run all queue: its status line, the list
-- of the reports it kept a line each, and one of those by its line, its pieces after. A piece stays well under Volt's
-- 8,192 B maxPacket
event runReport {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (state: enum { Refused, Running, Piece, Passed, Failed, Queue, Kept, Report }, text: string(0..4000)),
}

-- A client's report of one ClientCost window: the label the server opened it with, whether the client measured it
-- whole, and its line, which the server prints. A line stays well under Volt's 8,192 B maxPacket
event clientCost {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (label: string(1..64), measured: boolean, line: string(1..512)),
}

-- A client's ask that the server spawn the bot panel's bots: how many, how they move, and how many studs either way
-- of the asker they spread over, at most the play bound, nil for the whole map. The server refuses a count past its cap
event botSpawn {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (count: u16, behavior: enum { Idle, Walk, Sprint }, radius: u16(1..8192)?),
}

-- A client's ask that the server remove every bot the bot panel made
event botClear {
	from: Client,
	type: Reliable,
	call: SingleSync,
}

-- Whether a client's bot panel shows, the server sending it the numbers only while it does
event botWatch {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (shown: boolean),
}

-- Why the server refused a client's bot panel ask, or what a spawn it took could not build
event botRefused {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (reason: string(1..200)),
}

-- The server's numbers over the last second for a client whose bot panel shows, with the panel's bots on the server.
-- The text stays well under Volt's 8,192 B maxPacket
event botStats {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (made: u16, text: string(0..1000)),
}
