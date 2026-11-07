--[[
    A player's reports reach them over the dev scope with their kind and
    measurement, numbers to six digits and text cut to the schema's bound,
    the burst at once and no more, and the next carries the count dropped
--]]

--!strict
local task = require("@lune/task")

local Server = require("../../Fixtures/Exploits/Server")

local STEPS: number = 3 -- Mock steps a flushed send takes to reach the other side's listener
local OVER: number = 5 -- Reports past the burst in one instant
local DETAIL_BYTES: number = 64 -- The schema's bound on a report's detail

type Heard = { kind: string, detail: string, dropped: number }

return function (): (boolean, string | nil)
	local rig: Server.Rig = Server.load()
	local loaded: any = rig.loaded
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local Network: any = rig.network
	local rate: { perSecond: number, burst: number } = rig.require(server.Config.Forward).rate

	-- In Studio the kit is for anyone, so the player is sent their reports
	rig.studio(true)
	local fire: (player: any, kind: string, measurement: number | string) -> () = rig.start()

	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]
	local heard: { Heard } = {}
	client.report.on(function (kind: string, detail: string, dropped: number)
		table.insert(heard, { kind = kind, detail = detail, dropped = dropped })
	end)

	local function deliver()
		Network.flush()
		for _ = 1, STEPS do
			loaded.mock:step()
		end
	end

	-- The clock barely moves in a loop this short, so the burst is all the room there is
	for index: number = 1, rate.burst + OVER do
		fire(player, "ahead", index)
	end

	deliver()
	if #heard ~= rate.burst then
		return false,
			`{rate.burst + OVER} reports in one instant reached the player {#heard} times, not the burst's {rate.burst}`
	elseif heard[1].kind ~= "ahead" or heard[1].detail ~= "1" or heard[1].dropped ~= 0 then
		return false, `The first report arrived as {heard[1].kind}, "{heard[1].detail}", {heard[1].dropped} dropped`
	end

	-- Room for one more comes back at the rate
	task.wait(2 / rate.perSecond)
	fire(player, "band", 0.123456789)
	fire(player, "packet", string.rep("x", DETAIL_BYTES + 10))
	deliver()

	local band: Heard?, packet: Heard? = heard[rate.burst + 1], heard[rate.burst + 2]
	if not band or not packet then
		return false, `After the rate gave room back, {#heard - rate.burst} more reports arrived, not 2`
	elseif band.kind ~= "band" or band.detail ~= "0.123457" then
		return false, `A number arrived as {band.kind} "{band.detail}", not to six digits`
	elseif band.dropped ~= OVER then
		return false, `The next report carried {band.dropped} dropped, not the {OVER} past the burst`
	elseif #packet.detail ~= DETAIL_BYTES then
		return false, `A detail {DETAIL_BYTES + 10} bytes long arrived {#packet.detail} long, not cut to the bound`
	end

	return true, nil
end
