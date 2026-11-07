--[[
    The corrected event takes the dev game's own rate, not its schema's:
    past the configured burst in one instant, a client's replays are refused
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local STEPS: number = 3 -- Mock steps a fire takes to reach the server, the handshake before it included
local OVER: number = 1 -- Replays sent past the burst

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local Corrections: any = loaded.require(server.Corrections)
	local burst: number = loaded.require(server.Config.Corrections).rate.burst
	Corrections.start()

	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]
	Corrections.add(player)

	-- The mock's clock stands still, so no token comes back between these
	for _ = 1, burst + OVER do
		client.corrected.fire(0, false)
	end

	for _ = 1, STEPS do
		loaded.mock:step()
	end

	local counts: any = Corrections.get(player)
	if counts.small ~= burst then
		return false, `{burst + OVER} replays in one instant counted {counts.small}, where the burst is {burst}`
	end

	return true, nil
end
