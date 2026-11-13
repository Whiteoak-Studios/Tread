option clientOutput = "../src/Network/Client.luau"
option serverOutput = "../src/Network/Server.luau"
option runtime = "ReplicatedStorage.Packages.Volt"
option scope = Tread
option manualReplication = true

-- Tread's wire contract: the owner's Move, the buffers Tread packs itself, and the reliable slot table and calls
struct Command {
	moveX: i8(-127..127),
	moveZ: i8(-127..127),
	buttons: u16,
	yaw: u16,
	pitch: i16(-16384..16384),
	lean: i8(-127..127),
	headYaw: i8(-127..127),
	headPitch: i8(-127..127),
	fields: buffer(0..64),
}

enum Rig { A, B }

struct SlotEntry {
	slot: u16,
	taken: struct { rig: Rig, player: Instance? }?,
}

event Move {
	from: Client,
	type: Unreliable,
	call: SingleSync,
	data: (command: u16, acknowledged: u16, received: u16, delay: u8, commands: Command[0..8]),
}

event Relay {
	from: Server,
	type: Unreliable,
	call: SingleSync,
	data: buffer(0..896),
}

event Withheld {
	from: Server,
	type: Unreliable,
	call: SingleSync,
	data: buffer(0..896),
}

event Owner {
	from: Server,
	type: Unreliable,
	call: SingleSync,
	data: buffer(0..96),
}

event Feed {
	from: Server,
	type: Unreliable,
	call: SingleSync,
	data: buffer(0..160),
}

event Slots {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: SlotEntry[0..255],
}

event Death {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (character: u16, body: u16, pushX: i8, pushY: i8, pushZ: i8),
}

event Platform {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (platform: u8(1..127), tick: u32),
}

event Gravity {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (gravity: f64, tick: u32),
}

event Spectate {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (target: u16?, tick: u16),
}

event Shared {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (hash: u32, tick: u32),
}

event View {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (distance: u16(1..65535)),
}
