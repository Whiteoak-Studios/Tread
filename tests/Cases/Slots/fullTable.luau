--[[
    Players, NPCs and bodies can fill every slot, and on a full table each
    errors naming the reserve while a sleeper gets nil, until one is freed
--]]

--!strict
local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"
local CONSTANTS: string = "src/Constants.luau"
local RESERVE: number = 296 -- Frontier Zero's held-back slots
local KINDS: { string } = { "Player", "Npc", "Body" }

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local count: number = Environment.load(CONSTANTS).SLOTS

	Slots.start(RESERVE)

	for index: number = 1, count do
		local kind: string = KINDS[index % #KINDS + 1]
		local slot: number?, generation: number? = Slots.take(kind)
		if slot == nil or generation == nil then
			return false, `A {kind} found no slot with {index - 1} of {count} taken`
		end
	end

	for _, kind: string in KINDS do
		local took: boolean, problem: any = pcall(Slots.take, kind)
		if took then
			return false, `A {kind} took a slot from a full table`
		end

		local message: string = tostring(problem)
		if not message:find("slots.reserve", 1, true) or not message:find(`{RESERVE}`, 1, true) then
			return false, `A {kind} on a full table failed with "{message}", which names no reserve of {RESERVE}`
		end
	end

	local sleeper: number?, generation: number? = Slots.take("Sleeper")
	if sleeper ~= nil or generation ~= nil then
		return false, `A sleeper on a full table got slot {sleeper} and generation {generation}, not nil`
	end

	Slots.release(count // 2)

	local freed: number? = Slots.take("Player")
	if freed ~= count // 2 then
		return false, `The one freed slot went out as {freed}, not {count // 2}`
	end

	local again: boolean = pcall(Slots.take, "Body")
	if again then
		return false, "A body took a slot once the freed one was taken again"
	end

	return true, nil
end
