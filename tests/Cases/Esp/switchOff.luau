--[[
    Switching off removes every box, marker and the count and leaves no frame
    drawing, while every block still reaches Tread's client, and switching on
    again draws each slot at its last record, those heard while off included
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Rig = require("../../Fixtures/Esp/Rig")

local FIRST: number = 3 -- Drawn before the ESP is switched off
local LATER: number = 4 -- Heard only while it is off
local TICK: number = 50
local FRAMES: number = 3
local CLOSE: number = 1e-3

local function near(a: any, b: vector): boolean
	return math.abs(a.X - b.x) < CLOSE and math.abs(a.Y - b.y) < CLOSE and math.abs(a.Z - b.z) < CLOSE
end

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local switch: (on: boolean) -> () = rig.startEsp()
	local lift: vector = vector.create(0, rig.shared.step.standing / 2, 0)
	local first: vector = vector.create(5, 0, -5)
	local later: vector = vector.create(-20, 3, 12)

	rig.slots({ { slot = FIRST, generation = 1, rig = "A" }, { slot = LATER, generation = 1, rig = "A" } })
	switch(true)
	rig.relay({
		tick = TICK,
		reveals = { { slot = FIRST, generation = 1, kind = "Npc" } },
		records = { { slot = FIRST, generation = 1, position = first, word = rig.word({}) } },
		footsteps = { { at = first, kind = "Walk", material = roblox.Enum.Material.Grass } },
	})
	rig.frames(FRAMES)

	local anchor: any = rig.slot(FIRST)
	if not anchor or not rig.count() or #rig.markers() ~= 1 then
		return false, "The ESP drew no box, count or marker to switch off"
	end

	switch(false)

	if rig.drawn() or rig.count() then
		return false, "Switching off left the ESP's folder or count drawn"
	elseif anchor.Parent ~= nil then
		return false, "Switching off left a slot's box in the game"
	end

	-- A frame still connected would throw here, drawing while off, and Tread's client still draws what it hears
	local before: number = #rig.pool.of("checkout")
	rig.relay({
		tick = TICK + 1,
		reveals = { { slot = LATER, generation = 1, kind = "Npc" } },
		records = { { slot = LATER, generation = 1, position = later, word = rig.word({}) } },
	})
	rig.frames(FRAMES)

	if rig.drawn() or rig.count() then
		return false, "A block heard while off drew something"
	elseif #rig.pool.of("checkout") ~= before + 1 then
		return false, "Tread's client didn't draw the slot revealed while the ESP was off"
	end

	switch(true)
	rig.frames(FRAMES)

	local again: any = rig.slot(FIRST)
	local heard: any = rig.slot(LATER)
	if not again or not near(again.CFrame.Position, first + lift) then
		return false, "Switching on again drew no box at slot 3's last record"
	elseif not heard or not near(heard.CFrame.Position, later + lift) then
		return false, "Switching on again drew no box at the record slot 4 sent while the ESP was off"
	elseif #rig.markers() ~= 0 then
		return false, "Switching on again showed a marker from before the switch went off"
	elseif not rig.count() or not string.find(rig.count().Text, "1 slots", 1, true) then
		return false, "Switching on again showed no count of the last block's one slot"
	end

	switch(false)

	if rig.drawn() or rig.count() then
		return false, "The second switch off left the ESP's folder or count drawn"
	end

	return true, nil
end
