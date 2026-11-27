--[[
    Sleepers hold at most the slots the reserve leaves them, by a take or by
    a slot turning sleeper, while players, NPCs and bodies get the held-back
    slots and any slot past their own share
--]]

--!strict
local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"
local CONSTANTS: string = "src/Constants.luau"
local RESERVE: number = 296 -- Frontier Zero's held-back slots
local SMALL_RESERVE: number = 2
local BODIES: number = 10 -- More bodies than the small reserve holds back

return function (): (boolean, string | nil)
	local Slots = Environment.load(SLOTS)
	local count: number = Environment.load(CONSTANTS).SLOTS
	local share: number = count - RESERVE
	local sleepers: { number } = {}

	Slots.start(RESERVE)

	for _ = 1, share do
		local slot: number? = Slots.take("Sleeper")
		if slot == nil then
			return false, `A sleeper was refused with {#sleepers} of its {share} slots held`
		end

		table.insert(sleepers, slot)
	end

	local over: number?, overGeneration: number? = Slots.take("Sleeper")
	if over ~= nil or overGeneration ~= nil then
		return false, `A sleeper past its share of {share} got slot {over}`
	elseif Slots.count("Sleeper") ~= share then
		return false, `Sleepers hold {Slots.count("Sleeper")} slots, not their share of {share}`
	end

	-- The held-back slots go to players, NPCs and bodies
	local player: number? = Slots.take("Player")
	if player == nil then
		return false, "A player found no held-back slot"
	end

	Slots.setEntry(player, { kind = "Player", rig = "A" })

	for _ = 2, RESERVE do
		Slots.take("Npc")
	end

	-- A slot turning sleeper past the share changes nothing
	local turned: boolean = Slots.setEntry(player, { kind = "Sleeper", rig = "A" })
	local _, held: any = Slots.get(player)
	if turned or held.kind ~= "Player" then
		return false, "A player's slot turned sleeper while sleepers held their whole share"
	elseif Slots.count("Sleeper") ~= share or Slots.count("Player") ~= 1 then
		return false, "A refused turn to sleeper moved the counts"
	end

	-- Under the share, a released sleeper's slot goes to a sleeper again, and the same turn goes through
	Slots.release(sleepers[1])

	local again: number? = Slots.take("Sleeper")
	if again ~= sleepers[1] then
		return false, `A sleeper under its share got slot {again}, not the one a sleeper freed`
	end

	Slots.release(sleepers[2])

	if not Slots.setEntry(player, { kind = "Sleeper", rig = "A" }) then
		return false, "A player's slot could not turn sleeper with a sleeper's slot free"
	elseif Slots.count("Sleeper") ~= share or Slots.count("Player") ~= 0 then
		return false, "A turn to sleeper did not move one slot from players to sleepers"
	end

	-- Past their own share, bodies still find slots
	local small = Environment.load(SLOTS)
	small.start(SMALL_RESERVE)

	for index: number = 1, BODIES do
		if small.take("Body") == nil then
			return false, `Body {index} found no slot with a reserve of {SMALL_RESERVE}`
		end
	end

	-- A reserve of every slot leaves sleepers none, and one of none leaves them all
	local none = Environment.load(SLOTS)
	none.start(count)

	if none.take("Sleeper") ~= nil then
		return false, "A sleeper took a slot when every slot was held back"
	end

	local all = Environment.load(SLOTS)
	all.start(0)

	for index: number = 1, count do
		if all.take("Sleeper") == nil then
			return false, `Sleeper {index} found no slot with nothing held back`
		end
	end

	return true, nil
end
