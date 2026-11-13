--[[
    The shot event is bound at the dev game's own rate: a client's reports
    are kept under it, each counter unwrapped nearest the newest, a clear
    forgets them, the burst holds, and a player who leaves is forgotten
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local STEPS: number = 3 -- Mock steps a fire takes to reach the server, the handshake before it included
local OVER: number = 1 -- Reports sent past the burst
local TARGET: number = 9

-- Wire sequences in arrival order and the counters each unwraps to: forward, across the wrap, and one arriving late
local WIRES: { number } = { 20, 40, 60, 10, 62 }
local COUNTERS: { number } = { 20, 40, 60, 74, 62 }

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local Hits: any = loaded.require(server.Hits)
	local burst: number = loaded.require(server.Config.Hits).rate.burst
	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]

	local function deliver()
		for _ = 1, STEPS do
			loaded.mock:step()
		end
	end

	Hits.start()
	if pcall(Hits.start) then
		return false, "Hits.start ran a second time"
	end

	for index: number, wire: number in WIRES do
		client.shot.fire(wire, index == 1 and TARGET or nil)
	end

	deliver()

	local reports: { any } = Hits.reports(player)
	if #reports ~= #WIRES then
		return false, `{#WIRES} reports were sent and {#reports} kept under the player`
	elseif reports[1].target ~= TARGET or reports[2].target ~= nil then
		return false, `The reports kept targets {reports[1].target} and {reports[2].target}, not {TARGET} and nil`
	end

	for index: number, want: number in COUNTERS do
		if reports[index].counter ~= want then
			return false, `Report {index}, wire {WIRES[index]}, unwrapped to {reports[index].counter}, not {want}`
		end
	end

	Hits.clear()
	if #Hits.reports(player) ~= 0 then
		return false, "A clear left the player's reports"
	end

	-- The mock's clock stands still, so no token comes back between these, and the reports above took theirs
	local left: number = burst - #WIRES
	for counter: number = 1, left + OVER do
		client.shot.fire(counter, nil)
	end

	deliver()

	if #Hits.reports(player) ~= left then
		return false, `{left + OVER} reports with {left} of the burst left kept {#Hits.reports(player)}`
	end

	loaded.mock:leave(player)
	if #Hits.reports(player) ~= 0 then
		return false, "A player who left kept their reports"
	end

	return true, nil
end
