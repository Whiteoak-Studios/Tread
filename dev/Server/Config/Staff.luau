--[[
    The staff scenarios' numbers: where each lays its floor, far from the
    city block and from one another, where its bodies and parts stand on
    it, and how long each of its waits may run before it fails
--]]

--!strict
return {
	floor = {
		size = Vector3.new(80, 2, 80), -- Studs, its top at the scenario's center
		lift = 0.5, -- Studs above a top a body is built at, so it settles onto it
	},

	waits = {
		heartbeat = 5, -- Seconds the next Heartbeat may take
		settle = 5, -- Seconds a scenario's bodies may take to land on its floor
		landing = 2, -- Seconds past the teleport timeout a teleport may take to land
		heard = 5, -- Ticks onTeleported is still listened to after a landing, so a second call would show
		steps = 5, -- Ticks after an input or a field changes before its effect is read, past the commands already sent
		slack = 1, -- Seconds a count of ticks may run past its length at the simulation rate
	},

	close = 0.01, -- Studs a place may sit from where it should, past float32 rounding
	facing = 0.001, -- Radians a facing may sit from the look it came from
	rest = 0.05, -- Studs above a top a resting body's feet may stand, past the skin

	modes = {
		center = Vector3.new(-300, 1010, 0),
		lane = 12, -- Studs along Z between lanes, so no lane's bodies meet another's
		start = -8, -- Studs along X from the center each mover is built at
		obstacle = 4, -- And each obstacle, the block's center among them
		block = Vector3.new(8, 2, 8), -- The block a Noclip body is left inside, lower than the hull is tall
		stop = 2, -- Studs short of the block's center the flyer is told to stop, so the commands already sent leave it inside
		through = 0.5, -- Studs past touching a mover's hull must reach beyond an obstacle's to count as through it
		short = 1, -- Studs short of touching the held walker may stop and still count as having reached the control
		still = 3, -- Ticks the flyer must hold its place before it returns to Walk
		window = 10, -- Relay ticks the history is read over
		pass = 5, -- Seconds the movers may take to pass their obstacles, and the flyer to come to rest in the block
	},

	invisible = {
		center = Vector3.new(-300, 1010, 200),
		apart = 6, -- Studs along X between the real player's body and the bot's, nothing between them
		team = 1, -- The team the bot and its teammate viewer share
		reveal = 5, -- Seconds the bot may take to reach a view, anti-ESP's first test of the pair included
		window = 10, -- Relay ticks each phase is read over
	},

	spectate = {
		center = Vector3.new(-300, 1010, 400),
		spacing = 6, -- Studs between neighboring bots on the floor
		columns = 8, -- Bots a row
		focus = 1, -- Seconds the focus part may take to follow, five periods of the slow pass's 5 Hz
		window = 10, -- Relay ticks spectatorsOf is read over while a spectate runs
	},

	teleport = {
		center = Vector3.new(-300, 1010, 600),
		platform = 120, -- The test platform's id, clear of the dev elevator's 1 and the Wiring scenario's 127
		deck = Vector3.new(40, 1, 40), -- The platform's one box
		height = 3, -- Studs above the floor's top the deck's center stands
		walking = 0.5, -- The share of the walk speed the mover must reach on the deck before it is teleported
		along = 50, -- Studs along the plaza the real player is moved
		probe = 20, -- Studs above and below a destination its ground is cast for
		cancel = 10, -- Ticks a cancelled or refused teleport is listened for

		-- Where each bot stands and is sent, from the center, all off the deck
		spots = {
			mover = Vector3.new(30, 0, 30),
			replacer = Vector3.new(-30, 0, 0),
			first = Vector3.new(-30, 0, 30),
			second = Vector3.new(-30, 0, -30),
			cancelled = Vector3.new(30, 0, 0),
			away = Vector3.new(30, 0, -30),
		},
	},

	downed = {
		center = Vector3.new(-300, 1010, 800),
		lane = 10, -- Studs along X between the crawler's lane, the standing walker's and the faller's
		gap = 1.6, -- Studs from the crawler's hull front to the slab's near edge
		slab = Vector3.new(24, 1, 6), -- Across both lanes, a stud thick, and 6 studs along the crawl
		drop = 6, -- Studs above the floor the falling body is built at, past the landing airtime
		window = 40, -- Ticks each crawl and the revive are measured over
		share = 0.75, -- The least share of the crawl speed the crawl must reach, so a stuck body fails
		faster = 0.05, -- Studs a second a crawl may pass the cap by, past the step's 1/512-stud quantum
		still = 0.01, -- Studs a body being revived may move over the window
		short = 1, -- Studs short of the slab's edge the standing walker may stop and still count as having reached it
		hold = 10, -- Ticks a revived body is read crouched under the slab
		under = 10, -- Seconds the crawl may take to reach under the slab, and the walk to leave it
	},
}
