--[[
    Started after the slot table came, the ESP still draws every record,
    labelled by its reveal's kind, or as unknown when it heard none, and a
    later slot table entry names the Player again
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out Instance

local Rig = require("../../Fixtures/Esp/Rig")

local PLAYER: number = 3
local QUIET: number = 4 -- Revealed before the ESP started, so it hears no reveal
local TICK: number = 50
local FRAMES: number = 3

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local other: any = roblox.Instance.new("Player")
	other.Name = "Other"

	local function record(slot: number): { [string]: any }
		return { slot = slot, generation = 1, position = vector.create(slot, 0, 0), word = rig.word({}) }
	end

	rig.slots({
		{ slot = PLAYER, generation = 1, rig = "A", player = other },
		{ slot = QUIET, generation = 1, rig = "A" },
	})
	rig.relay({ tick = TICK, reveals = { { slot = QUIET, generation = 1, kind = "Npc" } }, records = { record(QUIET) } })

	local switch: (on: boolean) -> () = rig.startEsp()
	switch(true)
	rig.relay({
		tick = TICK + 1,
		reveals = { { slot = PLAYER, generation = 1, kind = "Player" } },
		records = { record(PLAYER), record(QUIET) },
	})
	rig.frames(FRAMES)

	local _, _, playerLabel: any = rig.slot(PLAYER)
	local _, _, quietLabel: any = rig.slot(QUIET)
	if not playerLabel or not string.find(playerLabel.Text, "Player", 1, true) then
		return false, "A player's record the ESP heard no slot table for drew no box named by its kind"
	elseif not quietLabel or not string.find(quietLabel.Text, "Unknown", 1, true) then
		return false, "A record with no reveal and no slot table heard drew no box named unknown"
	end

	-- The table's entry again, then a record, which redraws the label at once
	rig.slots({ { slot = PLAYER, generation = 1, rig = "A", player = other } })
	rig.relay({ tick = TICK + 2, records = { record(PLAYER) } })
	rig.frames(FRAMES)

	if not string.find(playerLabel.Text, other.Name, 1, true) then
		return false, `Slot {PLAYER}'s label reads "{playerLabel.Text}" after the slot table named {other.Name}`
	end

	switch(false)

	return true, nil
end
