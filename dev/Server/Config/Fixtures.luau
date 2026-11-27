--[[
    The fixture handlers' numbers: the stage bullets fly in, how far a
    request's claimed source may lie from the server's eye and each request's
    reach, and where the shot scenario lays its floor and bots
--]]

--!strict
return {
	stage = "fixtures", -- The stage bullets fly in, directly after the history

	source = 5, -- Studs a request's claimed source may lie from the server's cleared eye, Frontier Zero's fire-origin leash

	reach = {
		loot = 7.5, -- Studs from the server's eye, Frontier Zero's interaction range
		swing = 7, -- Its melee reach for a tool with no range of its own: the 5-stud floor plus 2
		build = 32, -- Its MAX_BUILD_DISTANCE
	},

	scenario = {
		center = Vector3.new(300, 1010, 0), -- The floor's top, clear of the city block and every other scenario's floor
		floor = Vector3.new(20, 2, 80),
		lift = 0.5, -- Studs above the floor each bot is built at, so it settles onto it
		apart = 60, -- Studs along Z from the shooter to the target, three of the Bow's ticks of flight
		slot = 2, -- The weapon the shooter fires, the Bow
		settle = 2, -- Seconds before the shot, for both bodies to land and the shooter's eye to settle
		wait = 10, -- Seconds the shot may take to resolve before the run fails
	},
}
