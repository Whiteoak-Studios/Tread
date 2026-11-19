--[[
    The relay check's numbers: copy B's workers, deadlines and pool folder,
    the four seeded layouts, and the events every layout runs, each before
    its run or, for a call into the relay, in the window after it
--]]

--!strict
-- One layout: its seed and runs, its viewers in a square of a side around a center, how far each owned body moves and
-- turns and how often it jumps a run, the share of pairs hidden and the runs between reshuffles, and any other bodies
export type Layout = {
	seed: number,
	runs: number,
	viewers: number,
	center: vector,
	spread: number,
	step: number,
	turn: number, -- Radians either way
	jump: number, -- A body's chance a run
	hidden: number,
	shuffle: number,
	sleepers: number?,
	npcs: number?,
	bodies: number?, -- And as many of each kind, in a square of others around the center
	others: number?,
	moderator: vector?, -- With one, a moderator stands there and watches the first viewer from watch until unwatch
	watch: number?,
	unwatch: number?,
}

-- An event of every layout: the run it comes before, or after for a call, and the viewer it is about, the first
-- viewer's index 1, with any other one it names
export type Event = {
	run: number,
	event: string,
	viewer: number,
	other: number?,
}

return {
	workers = 2, -- The fewest Actor workers copy B runs on, more when the server started more
	deadline = 1, -- Seconds copy B's round may take to land, the relay.timeout the dev place starts with
	ready = 10, -- Seconds copy B's workers have to be ready before the layout's first run
	pool = "TreadRelayWorkers", -- The folder the relay's front puts its pool in under ServerScriptService
	renamed = "TreadRelayWorkersCheck", -- What copy B's pool folder is renamed to the moment it is made
	home = "TreadRelayCheck", -- The folder under ServerStorage the copies' clones sit in
	listed = 20, -- The mismatches a report lists, past which it gives only their count
	busy = 95000, -- B a second of traffic that leaves a viewer little of its 96 KB hard room
	near = 250, -- Studs, a phone's render distance
	far = 1000, -- The dev place's relevancy.leave
	observed = 3, -- The first this many viewers of each layout have a tap sink

	-- The looks the calls set, in the dev and example tables' slot fields, and the held item, in their held fields
	look = { head = 7, torso = 65535 } :: { [string]: number },
	otherLook = { leg = 3 } :: { [string]: number },
	held = { item = 12, skin = 3 } :: { [string]: number },

	order = { "idle", "fight", "field", "spectate" },

	layouts = {
		idle = {
			seed = 101,
			runs = 24,
			viewers = 30,
			center = vector.create(0, 0, 0),
			spread = 600,
			step = 0,
			turn = 0,
			jump = 0,
			hidden = 0.1,
			shuffle = 8,
		},

		fight = {
			seed = 202,
			runs = 24,
			viewers = 30,
			center = vector.create(-192, 0, -192), -- Where cells of relevancy.leave from the play bound meet
			spread = 100,
			step = 0.8,
			turn = 0.3,
			jump = 0.05,
			hidden = 0.2,
			shuffle = 5,
		},

		field = {
			seed = 303,
			runs = 24,
			viewers = 20,
			center = vector.create(0, 0, 0),
			spread = 3000,
			step = 20, -- So pairs come into range and leave it
			turn = 0.3,
			jump = 0.05,
			hidden = 0.2,
			shuffle = 6,
			sleepers = 200,
			npcs = 10,
			bodies = 10,
			others = 4000,
		},

		spectate = {
			seed = 404,
			runs = 24,
			viewers = 12,
			center = vector.create(808, 0, 808),
			spread = 80,
			step = 0.8,
			turn = 0.3,
			jump = 0.05,
			hidden = 0.3,
			shuffle = 5,
			moderator = vector.create(3000, 0, 3000),
			watch = 4,
			unwatch = 20,
		},
	} :: { [string]: Layout },

	schedule = {
		{ run = 3, event = "look", viewer = 3 },
		{ run = 4, event = "held", viewer = 4 },
		{ run = 5, event = "invisible", viewer = 5 },
		{ run = 6, event = "reveal", viewer = 6 },
		{ run = 7, event = "shotNear", viewer = 1, other = 7 },
		{ run = 8, event = "visible", viewer = 5 },
		{ run = 8, event = "otherLook", viewer = 4 },
		{ run = 9, event = "near", viewer = 8 },
		{ run = 10, event = "busy", viewer = 3 },
		{ run = 11, event = "revealAll", viewer = 2 },
		{ run = 12, event = "far", viewer = 8 },
		{ run = 13, event = "calm", viewer = 3 },
		{ run = 14, event = "leave", viewer = 9 },
		{ run = 16, event = "death", viewer = 7 },
		{ run = 18, event = "rejoin", viewer = 9 },
	} :: { Event },
}
