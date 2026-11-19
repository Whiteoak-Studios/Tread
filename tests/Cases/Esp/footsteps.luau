--[[
    Each footstep entry a block carries while the ESP draws shows a marker
    where the step fell, a marker for each of a block's entries, for a short
    while only, and an entry heard while it was switched off shows none
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local Rig = require("../../Fixtures/Esp/Rig")

local TICK: number = 50
local FRAMES: number = 3
local CLOSE: number = 1e-3 -- Studs a marker may sit from its step, since a part holds float32
local LIFE: number = 2 -- Seconds the ESP shows a footstep's marker
local MARGIN: number = 0.25

local function shows(markers: { any }, at: vector): boolean
	for _, position: any in markers do
		if math.abs(position.X - at.x) < CLOSE and math.abs(position.Y - at.y) < CLOSE then
			if math.abs(position.Z - at.z) < CLOSE then
				return true
			end
		end
	end

	return false
end

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local switch: (on: boolean) -> () = rig.startEsp()
	local grass: any = roblox.Enum.Material.Grass

	local first: vector = vector.create(10.5, 2, -30.25)
	local second: vector = vector.create(-4, 0.5, 18)
	local third: vector = vector.create(-5.5, 0.5, 19.5)

	-- Heard while off, it shows nothing then or once the ESP is on
	rig.relay({ tick = TICK, footsteps = { { at = first, kind = "Walk", material = grass } } })
	switch(true)
	rig.frames(FRAMES)

	if #rig.markers() ~= 0 then
		return false, `A footstep heard while the ESP was off showed {#rig.markers()} markers once it was on`
	end

	rig.relay({ tick = TICK + 1, footsteps = { { at = first, kind = "Sprint", material = grass } } })
	rig.frames(FRAMES)

	local shown: { any } = rig.markers()
	if #shown ~= 1 or not shows(shown, first) then
		return false, `A footstep at {first} showed {#shown} markers, not one there`
	end

	rig.relay({
		tick = TICK + 2,
		footsteps = {
			{ at = second, kind = "Jump", material = grass },
			{ at = third, kind = "Land", material = grass },
		},
	})
	rig.frames(FRAMES)

	shown = rig.markers()
	if #shown ~= 3 or not shows(shown, second) or not shows(shown, third) then
		return false, `A block of two more footsteps left {#shown} markers showing, not three with both new ones`
	end

	-- Every marker goes once its step is older than its life
	task.wait(LIFE + MARGIN)
	rig.frames(FRAMES)

	if #rig.markers() ~= 0 then
		return false, `{#rig.markers()} markers still showed {LIFE + MARGIN} s after their steps`
	end

	switch(false)

	return true, nil
end
