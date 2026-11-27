--[[
    On a dev server started with no crowd cap, the crowdCap lever refuses
    on, naming why, sets none, and leaves the session's other levers set and
    put back, and the levers run's after half that flips it fails naming it
--]]

--!strict
local Step = require("../../Fixtures/DevStep/Step")

local REFUSAL: string = "crowdCap refused on: the dev server started with no tiers.crowd to set"

-- Each half drives and gives a figure, so its table prints
local function answer(_: string, _: string?): (boolean, string, { [string]: number }?)
	return true, "drove and cleaned up", { skipped = 1 }
end

-- How many times a text holds another, as plain text
local function count(text: string, part: string): number
	local found: number = 0
	local from: number? = string.find(text, part, 1, true)
	while from do
		found += 1
		from = string.find(text, part, from + 1, true)
	end

	return found
end

return function (): (boolean, string | nil)
	-- A server started with no tiers.crowd, so the relay holds none
	local mounted: Step.Mounted = Step.load(answer)
	mounted.settings.tiers.crowd = nil
	mounted.Relay.setCrowd(nil)
	local Levers: any = mounted.Levers

	-- 1) Session 2's flip on: the bands and anti-ESP's workers set, the crowd cap refused and still none
	local states: { [string]: boolean }, refused: { string } = Levers.flip(2, true)
	if table.concat(refused, ",") ~= REFUSAL then
		return false, `Session 2's flip on refused {table.concat(refused, ",")}`
	elseif mounted.Relay.crowd() ~= nil then
		return false, "The refused crowd cap was set all the same"
	elseif #mounted.Relay.bands() ~= 3 or not mounted.AntiEsp.workersOn() then
		return false, "The flip on that refused the crowd cap left the session's other levers unset"
	elseif states.crowdCap ~= false then
		return false, `The flip found crowdCap {states.crowdCap}, not off`
	end

	local unrestored: { string } = Levers.restore(states)
	if #unrestored > 0 or mounted.Relay.crowd() ~= nil or mounted.AntiEsp.workersOn() then
		return false, `After restore the levers stood otherwise, refusing {table.concat(unrestored, ",")}`
	end

	-- 2) The levers run, which flips the crowd cap by its name: its S4 crowdCap after half fails naming the refusal
	-- once, and no other half or its hold refuses anything
	local passed: boolean, reason: string? = mounted.BenchStep("levers")
	local text: string = reason or ""
	if passed then
		return false, "A levers run whose crowdCap after half's crowd cap was refused passed"
	elseif count(text, `Bots S4/after's levers refused: {REFUSAL}`) ~= 1 then
		return false, `The levers run named the refusal otherwise than once, for S4 crowdCap's after half:\n{text}`
	elseif count(text, "levers refused") ~= 1 then
		return false, `The levers run named a refusal for another half or its hold:\n{text}`
	end

	-- The rest of its halves ran as asked, and the levers stand as the server started them
	if #mounted.asked ~= 6 then
		return false, `The levers run asked for {#mounted.asked} halves, not 6`
	elseif mounted.Relay.crowd() ~= nil or #mounted.Relay.bands() ~= 3 or mounted.AntiEsp.workersOn() then
		return false, "The run left session 2's levers other than as the server started them"
	elseif mounted.Relay.budget() == nil or mounted.Relay.underLoad() == nil then
		return false, "The run left the frame caps off"
	end

	return true, nil
end
