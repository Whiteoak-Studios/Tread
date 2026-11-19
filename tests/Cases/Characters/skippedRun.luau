--[[
    After a relay run a catch-up skipped, a player's ping sample weighs the
    two relay ticks since its last, and each focus share whose turn came on
    the skipped tick moves too, so every part still follows at about 5 Hz
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local PLAYERS: number = 4 -- One in each focus share, the example's 20 Hz relay over a 5 Hz move
local SPACING: number = 6 -- Studs between the players' bodies along X
local TELEPORT_Z: number = 8 -- Where the teleports set them down, a row on the fixture floor clear of its parts
local FIRST_PING: number = 0.05 -- Seconds each player's engine ping reports at first
local LATER_PING: number = 0.2 -- And the first player's from the catch-up on
local SETTLE: number = 4 -- One-tick Heartbeats first, so each body stands and each connection has sampled
local CATCH_UP: number = 2 -- The ticks each catch-up Heartbeat runs, the example's catch-up
local FOLLOWS: number = 2 -- Catch-up Heartbeats after the teleports' landing, four relay ticks, a full pass
local CLOSE: number = 1e-12 -- How near the round trip must be to the one the weights give
local NEAR: number = 0.1 -- Studs a focus part may sit from the body it follows

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		-- With no hook, and Lune's Workspace not streaming, a Player's teleport is ready at once
		settings.prestream = nil
	end)

	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)

	local players: { any } = {}
	local characters: { any } = {}
	for index: number = 1, PLAYERS do
		local player: any = roblox.Instance.new("Player")
		Pings[player] = FIRST_PING
		players[index] = player
		characters[index] = server:create(player, rig:at(index * SPACING, 0))
	end

	rig:tick(SETTLE)

	-- 1) The sample after the skipped run weighs two relay ticks' seconds, not one's
	local connection: any = Connections.get(players[1])
	local before: number = connection:rtt()
	Pings[players[1]] = LATER_PING
	rig.frames:run(CATCH_UP / rig.rate)

	local seconds: number = CATCH_UP / rig.shared.rates.relay
	local weight: number = 1 - math.exp(-seconds / rig.settings.rewind.rttSmoothing)
	local expected: number = before + weight * (LATER_PING - before)
	if math.abs(connection:rtt() - expected) > CLOSE then
		return false, `After a skipped run the round trip read {connection:rtt()}, not {expected}`
	end

	-- 2) Teleported, then only catch-up Heartbeats: every share's part follows within a full pass of relay ticks
	for index: number, character: any in characters do
		character:teleport(roblox.CFrame.new(-index * SPACING, rig.floor, TELEPORT_Z))
	end

	rig:tick(1)
	for _ = 1, FOLLOWS do
		rig.frames:run(CATCH_UP / rig.rate)
	end

	for index: number, player: any in players do
		local root: any = characters[index]:getState().root
		local part: any = player.ReplicationFocus
		if not part or (part.Position - root).Magnitude > NEAR then
			return false, `Player {index}'s focus part sat at {part and part.Position}, not at its body {root}`
		end
	end

	return true, nil
end
