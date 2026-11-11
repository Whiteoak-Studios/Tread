--[[
    The Changes scenario's numbers: where it lays its floor and sets the
    real player down, the area its bots walk round them, how long it warms
    up and reads the player's traffic for, and how long each wait may take
--]]

--!strict
return {
	center = Vector3.new(-2000, 900, 0), -- The floor's top, clear of the city block and every other scenario's floor
	floor = Vector3.new(120, 2, 120), -- Square, the player at its middle and every bot's walk on it
	area = Vector2.new(80, 80), -- What the bots roam, around the player
	lift = 0.5, -- Studs above the floor each body is set down at, so it settles onto it
	bots = 20,
	seed = 1, -- The run's generator, which each bot's spot, facing and walk are drawn from
	landed = 5, -- Studs across the ground from the floor's middle the player's teleport must land within
	warmup = 3, -- Seconds after the bots are built before the window, so every reveal is acknowledged
	window = 10, -- Seconds of traffic read
	interval = 1, -- Seconds between reads, the second Volt's count covers
	wait = 10, -- Seconds each wait may take before the run fails
}
