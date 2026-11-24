--[[
    Given all four cap keys, the start refuses none, sets the relay budget
    before the far rate under load that needs it, and each cap's getter reads
    its key's value; antiEsp.whole false and no far rate leave both off
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local NPC_BUDGET: number = 0.004 -- Seconds, each cap's value a number no default gives
local RELAY_BUDGET: number = 0.003
local UNDER_LOAD: { runs: number, scale: number } = { runs = 3, scale = 0.25 }
local TICKS: number = 3 -- Ticks run with every cap on, which raise no stage report

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.npcs.budget = NPC_BUDGET
		settings.antiEsp.whole = true
		settings.relay = { changes = true, budget = RELAY_BUDGET }
		settings.tiers.underLoad = UNDER_LOAD
	end)

	local started: boolean, failure: any = pcall(rig.start, rig)
	if not started then
		return false, `The start refused the four cap keys: {failure}`
	end

	local tread: any = rig.tread
	local AntiEsp: any = rig:require(tread.Server.AntiEsp)
	local Npcs: any = rig:require(tread.Server.Npcs)
	local Relay: any = rig:require(tread.Server.Relay)

	local underLoad: any = Relay.underLoad()
	if Npcs.budget() ~= NPC_BUDGET or Relay.budget() ~= RELAY_BUDGET or not AntiEsp.wholeOn() then
		local relaySet: string = `relay budget {Relay.budget()}, whole {AntiEsp.wholeOn()}`
		return false, `The start set the NPC budget {Npcs.budget()}, {relaySet}`
	elseif underLoad == nil or underLoad.runs ~= UNDER_LOAD.runs or underLoad.scale ~= UNDER_LOAD.scale then
		return false, "The start left the far rate under load unset or set it to other values"
	end

	rig:tick(TICKS)
	if #rig:reported("stage") ~= 0 then
		return false, `With every cap on, {TICKS} ticks reported stage {rig:reported("stage")[1]}`
	end

	-- whole given false, and a relay budget with no far rate under load
	local partial: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.antiEsp.whole = false
		settings.relay = { changes = true, budget = RELAY_BUDGET }
	end)

	partial:start()
	local partialEsp: any = partial:require(partial.tread.Server.AntiEsp)
	local partialNpcs: any = partial:require(partial.tread.Server.Npcs)
	local partialRelay: any = partial:require(partial.tread.Server.Relay)

	if partialEsp.wholeOn() or partialNpcs.budget() ~= nil or partialRelay.underLoad() ~= nil then
		return false, "antiEsp.whole false, or a key left out, turned its cap on"
	elseif partialRelay.budget() ~= RELAY_BUDGET then
		return false, `relay.budget alone set the relay budget {partialRelay.budget()}`
	end

	return true, nil
end
