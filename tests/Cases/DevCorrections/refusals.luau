--[[
    Only a player being counted is counted: a replay before counting began,
    after the player left, or of a size below 0 is dropped, a second add
    keeps the counts, a second start errors, and a read of anyone else is nil
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local STEPS: number = 3 -- Mock steps a fire takes to reach the server, the handshake before it included
local NEGATIVE: number = -1 -- Studs, a size no replay has

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local Corrections: any = loaded.require(server.Corrections)
	Corrections.start()

	local again: boolean = pcall(Corrections.start)
	if again then
		return false, "A second Corrections.start ran"
	end

	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]

	local function send(size: number)
		client.corrected.fire(size, false)

		for _ = 1, STEPS do
			loaded.mock:step()
		end
	end

	-- Before counting began
	send(0)

	if Corrections.get(player) ~= nil or Corrections.get({ Name = "Stranger" }) ~= nil then
		return false, "A player never added read as counted"
	end

	Corrections.add(player)
	send(NEGATIVE)
	send(0)

	local counts: any = Corrections.get(player)
	if counts.small ~= 1 or counts.large ~= 0 then
		local counted: string = `{counts.small} small and {counts.large} large`
		return false, `A replay before counting, one below 0 and one of 0 counted {counted}`
	end

	Corrections.add(player)
	if Corrections.get(player).small ~= 1 then
		return false, "A second add reset the player's counts"
	end

	Corrections.remove(player)
	send(0)
	Corrections.remove(player)

	if Corrections.get(player) ~= nil then
		return false, "A player removed still read as counted"
	end

	return true, nil
end
