--[[
    server:rewindFor rewinds a shot from one of the last 8 commands its
    character stepped: a claim inside the band is used as claimed, one far
    outside it gives way to the expected time and is reported as band, a
    command outside the last 8 is refused, and so is a bot with no character
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 30
local FAR: number = 10 -- Relay ticks a claim lies off the expected time, past the 2-tick band's widest
local KEPT: number = 8 -- The commands a character keeps for rewindFor

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local bot: any = rig.mock:addBot("Bot")
	server:create(bot, rig:at(0, 0))

	rig:tick(TICKS)

	-- The bot sends no Move, so its newest command is the stand-in numbered by the last tick, which waited none
	local delay: number = rig.settings.rewind.delayMin
	local expected: number = TICKS - (rig.settings.bots.rtt + delay) * rig.shared.rates.relay
	local claimed: number = expected + 0.5

	local time: number, inside: boolean = server:rewindFor(bot, TICKS, claimed)
	if not inside or math.abs(time - claimed) > 1e-9 then
		return false, `A claim half a tick off the expected {expected} gave {time}, inside {inside}`
	end

	local reported: number = #rig:reported("band")
	local retimed: number, within: boolean = server:rewindFor(bot, TICKS, expected - FAR)
	local bands: { number | string } = rig:reported("band")

	if within or math.abs(retimed - expected) > 1e-9 then
		return false, `A claim {FAR} ticks off gave {retimed}, inside {within}, not the expected {expected}`
	elseif #bands ~= reported + 1 or math.abs((bands[#bands] :: number) + FAR) > 1e-9 then
		return false, `A claim {FAR} ticks off gave {#bands - reported} band reports, measuring {bands[#bands]}`
	end

	if pcall(server.rewindFor, server, bot, TICKS - KEPT, claimed) then
		return false, "rewindFor took a command older than the last 8 the character stepped"
	elseif pcall(server.rewindFor, server, rig.mock:addBot("Nobody"), TICKS, claimed) then
		return false, "rewindFor took a bot with no character"
	end

	return true, nil
end
