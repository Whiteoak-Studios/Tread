--[[
    The Playback scenario's numbers: its floor away from everything else,
    the two bots on it, how long it records, the parts it sends the clip in
    and how long it waits on the player's client
--]]

--!strict
return {
	rate = { perSecond = 2, burst = 4 }, -- Played reports a second, where one ends each playback

	-- The floor's top center. Inside the record's -1,024 to 1,024 height window and the play bound's 8,192 studs either
	-- way, or every record clamps there, and away from the city block, the map and the other scenarios' floors
	center = Vector3.new(-2000, 900, -2000),
	floor = Vector3.new(40, 2, 120), -- Long along Z, the walker's line
	lift = 0.5, -- Studs above the floor each bot is built at, so it settles onto it
	start = 25, -- Studs along +Z from the center the walker starts at, so it passes the watcher partway through
	aside = 6, -- Studs along +X from the walker's line the watcher stands at, level with the center

	settle = 1, -- Seconds after both bots are built before the recording starts
	seconds = 3, -- Seconds the clip records
	recordWait = 6, -- Seconds the recording may take to fill before the run fails
	streamWait = 5, -- Seconds the player's client may take to stream the floor in
	partBytes = 4096, -- Bytes each part carries at most, the clip event's own bound in Dev.volt
	playWait = 300, -- Seconds the player's client has to play the clip and say so
}
