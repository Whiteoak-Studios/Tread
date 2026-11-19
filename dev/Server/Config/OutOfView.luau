--[[
    The OutOfView scenario's numbers: where it lays its floor, where its
    four targets stand from the viewer and the circles they walk, the tick
    the viewer turns on, and the scenario's tolerances and waits
--]]

--!strict
return {
	center = Vector3.new(2000, 900, -2000), -- The floor's top, clear of the city block and every other scenario's floor
	floor = Vector3.new(150, 2, 150), -- Square, the viewer at its middle and every target's circle on it
	lift = 0.5, -- Studs above the floor each bot is built at, so it settles onto it
	far = 60, -- Studs from the viewer to the targets in front, behind and to its side, clear past the out-of-view radius
	near = 10, -- Studs to the one behind it inside the dev server's out-of-view radius
	circle = 3, -- Studs, the radius of the circle each target walks around its spot
	lead = 0.6, -- Radians round its circle ahead of where it stands that a target walks toward
	turn = 40, -- The viewer's ticks from its first OwnerState before its look turns round
	window = 20, -- Relay frames the count before the turn must cover at least
	slack = 2, -- Records each count may sit off what its rate gives over the window
	wait = 10, -- Seconds each wait may take before the run fails
}
