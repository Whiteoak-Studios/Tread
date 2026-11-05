--[[
    The slot table refuses a take before its start, a second start, a bad
    reserve, an unknown kind, a free or unknown slot and a malformed entry,
    and a refused entry changes nothing
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local SLOTS: string = "src/Server/Slots.luau"
local CONSTANTS: string = "src/Constants.luau"
local RESERVE: number = 296

type Refusal = { label: string, by: string, call: () -> () }

return function (): (boolean, string | nil)
	local count: number = Environment.load(CONSTANTS).SLOTS
	local unstarted = Environment.load(SLOTS)

	local early: boolean, problem: any = pcall(unstarted.take, "Player")
	if early or not tostring(problem):find("Slots.take", 1, true) then
		return false, `A take before start was not refused by Slots.take: {problem}`
	end

	-- Each bad reserve is tried on a table of its own, since one start would close the rest
	local reserves: { any } = { -1, count + 1, 1.5, 0 / 0, math.huge, `{RESERVE}`, false }
	for _, reserve: any in reserves do
		local fresh = Environment.load(SLOTS)
		local started: boolean, refusal: any = pcall(fresh.start, reserve)
		if started or not tostring(refusal):find("Slots.start", 1, true) then
			return false, `Slots.start took the reserve {reserve}`
		end
	end

	local Slots = Environment.load(SLOTS)
	local changes: number = 0

	Slots.start(RESERVE)
	Slots.onChange(function ()
		changes += 1
	end)

	local taken: number = Slots.take("Player")
	Slots.setEntry(taken, { kind = "Player", rig = "A" })
	changes = 0

	local part: any = roblox.Instance.new("Part")
	local free: number = count - 1

	local refusals: { Refusal } = {
		{
			label = "a second start",
			by = "Slots.start",
			call = function ()
				Slots.start(RESERVE)
			end,
		},
		{
			label = "an unknown kind",
			by = "Slots.take",
			call = function ()
				Slots.take("Ghost")
			end,
		},
		{
			label = "a free slot to release",
			by = "Slots.release",
			call = function ()
				Slots.release(free)
			end,
		},
		{
			label = "a slot below the table to release",
			by = "Slots.release",
			call = function ()
				Slots.release(-1)
			end,
		},
		{
			label = "a slot past the table to release",
			by = "Slots.release",
			call = function ()
				Slots.release(count)
			end,
		},
		{
			label = "a free slot to set",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(free, { kind = "Player", rig = "A" })
			end,
		},
		{
			label = "a missing entry",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(taken, nil)
			end,
		},
		{
			label = "an entry of an unknown kind",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(taken, { kind = "Ghost", rig = "A" })
			end,
		},
		{
			label = "an entry of an unknown rig mode",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(taken, { kind = "Player", rig = "C" })
			end,
		},
		{
			label = "an entry whose player is a Part",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(taken, { kind = "Player", rig = "A", player = part })
			end,
		},
		{
			label = "an entry whose player is a bot",
			by = "Slots.setEntry",
			call = function ()
				Slots.setEntry(taken, { kind = "Player", rig = "A", player = { Name = "Bot" } })
			end,
		},
		{
			label = "a slot below the table to read",
			by = "Slots.get",
			call = function ()
				Slots.get(-1)
			end,
		},
		{
			label = "a slot past the table to read",
			by = "Slots.get",
			call = function ()
				Slots.get(count)
			end,
		},
		{
			label = "a fractional slot to read",
			by = "Slots.get",
			call = function ()
				Slots.get(0.5)
			end,
		},
		{
			label = "a string slot to read",
			by = "Slots.get",
			call = function ()
				Slots.get("0")
			end,
		},
		{
			label = "an unknown kind to count",
			by = "Slots.count",
			call = function ()
				Slots.count("Ghost")
			end,
		},
		{
			label = "a missing change callback",
			by = "Slots.onChange",
			call = function ()
				Slots.onChange(nil)
			end,
		},
	}

	for _, refusal: Refusal in refusals do
		local ran: boolean, failure: any = pcall(refusal.call)
		if ran then
			return false, `{refusal.by} took {refusal.label}`
		elseif not tostring(failure):find(refusal.by, 1, true) then
			return false, `{refusal.label} failed with "{failure}", not {refusal.by}'s refusal`
		end
	end

	local _, entry: any = Slots.get(taken)
	if changes ~= 0 or entry.kind ~= "Player" or entry.rig ~= "A" or entry.player ~= nil then
		return false, "A refused call changed the slot table or reported a change"
	end

	local valid: { any } = { 0, count - 1 }
	local invalid: { any } = { -1, count, 0.5, 0 / 0, "0", false }

	for _, value: any in valid do
		if not Slots.valid(value) then
			return false, `Slots.valid refused the slot {value}`
		end
	end

	for _, value: any in invalid do
		if Slots.valid(value) then
			return false, `Slots.valid took {value} as a slot`
		end
	end

	return true, nil
end
