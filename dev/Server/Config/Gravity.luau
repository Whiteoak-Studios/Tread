--[[
    The Gravity scenario's numbers: where its bot falls from and its sleeper
    drops, the gravity it changes to and when, how many ticks after it are
    checked, how close each check must come, and how long each wait may take
--]]

--!strict
return {
	at = Vector3.new(200, 1020, 200), -- Where the bot's character is built, in open air inside the 1,024-stud window
	changed = 30, -- Studs/s², the gravity the run changes to
	airborne = 6, -- Ticks the bot falls under the shared table's gravity before the change
	checked = 10, -- Ticks after the change's own tick the fall is checked through
	close = 1 / 64, -- Studs/s a tick's vertical speed may sit off the step's own update
	read = 1e-3, -- Studs/s² Workspace.Gravity may read off a value set, which it holds as a float

	sleeper = {
		at = Vector3.new(210, 1020, 200), -- Where the sleeper is made, beside the bot's spot in the same open air
		drop = 18, -- Studs straight down its move takes it, to 1,002 up, inside the 1,024-stud window
		changeAfter = 8, -- Relay ticks after its move's tick the change lands on, 0.4 s at 20 Hz
		after = 4, -- Relay ticks past the fall's end under the change that are read too, every one at rest
		close = 1e-3, -- Studs a sampled place may sit off Math.fall's, which a Vector3 holds as float32
	},

	waits = {
		airborne = 5, -- Seconds the bot may take to fall its ticks before the change
		checked = 5, -- Seconds the server may take to run the checked ticks
		sleeper = 5, -- Seconds the server may take to reach the sleeper's change, and again to run its fall out
	},
}
