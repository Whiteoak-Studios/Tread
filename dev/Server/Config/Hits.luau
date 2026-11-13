--[[
    G7's hit agreement numbers: the shot reports' rate, the floor and the
    shooter's spot away from everything else, the run's settle, warm-up and
    drain, and each case's weapon, targets, gait and length
--]]

--!strict
return {
	rate = { perSecond = 30, burst = 60 }, -- Shot reports a second, three times the shooter's 10 shots a second

	-- The shooter's feet, on the floor's top. Inside the record's -1,024 to 1,024 height window, or every record and
	-- history sample clamps there, and away from the city block, the map and the fixture shot's floor
	spot = Vector3.new(0, 900, 2000),
	floor = Vector3.new(200, 2, 760), -- From 30 studs behind the spot to 730 ahead of it along -Z
	behind = 30, -- Studs of floor behind the spot
	lift = 0.5, -- Studs above the floor each bot is built at, so it settles onto it
	width = 60, -- Studs across X each case's targets stand or roam in, centered on the spot's line

	settle = 3, -- Seconds after the shooter's teleport before the first case
	warmup = 3, -- Seconds each case's targets run before firing starts
	drain = 2, -- Seconds after firing stops for the last bullets to resolve and report
	interval = 1, -- Seconds between two reads of the shooter's ping
	seed = 1, -- Each case's targets' places and paths
	smoke = 10, -- Seconds each case fires for in the smoke run

	-- Each case's targets stand between near and far studs ahead of the spot, idle or sprinting about that band
	cases = {
		{ name = "still", weapon = 1, sprint = false, count = 6, near = 45, far = 105, seconds = 120 },
		{ name = "near", weapon = 1, sprint = true, count = 6, near = 45, far = 105, seconds = 120 },
		{ name = "longAkm", weapon = 1, sprint = true, count = 6, near = 550, far = 700, seconds = 120 },
		{ name = "longBow", weapon = 2, sprint = true, count = 6, near = 330, far = 430, seconds = 120 },
	},
}
