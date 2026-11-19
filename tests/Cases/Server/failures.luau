--[[
    Tread's own Volt failures are reported under Volt's kind names: Moves
    past the rate the settings give are rate, with the player, and what the
    server sends a player who never joined Tread's scope is departed
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Pings = require("../../Fixtures/Connections/Ping")
local Rig = require("../../Fixtures/Server/Rig")

local MOVES: number = 4 -- Moves fired in one frame, past a rate with a burst of 1
local PING: number = 0.05 -- Seconds the Lune player's engine ping reports

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.rates.move = { perSecond = 1, burst = 1 }
	end)

	local server: any = rig:start()
	local client: any = rig:require(rig.tread.Network.Client)
	local player: any = rig.mock.players[1]

	client.flush()
	rig:deliver()

	for _ = 1, MOVES do
		client.Move.fire(0, 0, 0, 0, {})
	end

	client.flush()
	rig:deliver()

	local rated: { Rig.Heard } = rig:reportedFor("rate", player)
	if #rated ~= MOVES - 1 or type(rated[1].measurement) ~= "string" then
		return false, `{MOVES} Moves at a burst of 1 gave {#rated} rate reports with Volt's detail, not {MOVES - 1}`
	end

	-- A Player the mock never joined gets a character, so every send to it finds no one there
	local stranger: any = roblox.Instance.new("Player")
	Pings[stranger] = PING
	server:create(stranger, rig:at(0, 0))
	rig:tick(1)

	if #rig:reportedFor("departed", stranger) == 0 then
		return false, "Sends to a player who never joined Tread's scope gave no departed report"
	end

	return true, nil
end
