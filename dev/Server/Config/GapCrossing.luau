--[[
    The GapCrossing check's numbers: its floor, the two walls and the gap
    between them, the four passes' viewer and path distances, the zone the
    client records in, and how long each step and wait may take
--]]

--!strict
return {
	-- The gap's middle on the floor's top: clear of every other scenario's floor, above the 1,000 studs no content
	-- reaches, and with every body on it inside the record's 1,024-stud height window
	center = Vector3.new(2000, 1010, -2000),
	margin = 10, -- Studs of floor past every viewer's spot and every path's end
	thickness = 2, -- The floor's, in studs

	wall = {
		length = 45, -- Studs along the line, each of the two
		height = 12,
		width = 1, -- Studs across the line
		inset = 0.2, -- Studs the occluder-only part sits inside its wall on every face
	},

	gap = 2, -- Studs between the two walls

	-- Studs from the wall line to the viewer's spot and to the target's path behind it, and how far either way of the
	-- gap the path runs, past where the walls' shadow ends, so each crossing starts and ends in the open
	passes = {
		{ viewer = 60, behind = 2, reach = 55 },
		{ viewer = 60, behind = 30, reach = 80 },
		{ viewer = 300, behind = 2, reach = 55 },
		{ viewer = 300, behind = 30, reach = 55 },
	},

	crossings = 3, -- Each pass's, alternating direction
	zone = 12, -- Studs either way of the gap the target is tracked through it and the client records its frames in
	lift = 0.5, -- Studs above the floor each body is set down at, so it settles onto it
	landed = 1, -- Studs across the ground from its spot the viewer's teleport must land within
	still = 0.1, -- Studs the viewer may move in a pass before the pass fails
	settle = 2, -- Seconds after the viewer lands, and after the target is built, before the next step
	slack = 2, -- Times a pass's own sprint time it may take before it fails
	seconds = 10, -- The longest the viewer's landing may take before the pass fails
	wait = 3, -- Seconds after a window ends it waits for the client's line
	rate = { perSecond = 1, burst = 2 }, -- The client's lines a second, one a crossing
	seed = 1, -- The target's, which a bot steered by hand never draws from
}
