--[[
    A slot's label gives its distance from the camera and its record's age,
    and once that record is more than a second old its box and label grey
    out, until its next record brings the color back
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes
local task = require("@lune/task")

local Rig = require("../../Fixtures/Esp/Rig")

local SLOT: number = 3
local TICK: number = 50
local FRAMES: number = 3
local STALE: number = 1 -- Seconds past which the ESP greys a box whose slot sent nothing newer
local MARGIN: number = 0.25
local DISTANCE: string = "40 studs" -- From the camera to the box's center, set below
local AGE: string = "([%d%.]+) s ago" -- The age a label gives

return function (): (boolean, string | nil)
	local rig: any = Rig.new()
	local switch: (on: boolean) -> () = rig.startEsp()
	switch(true)

	local step: any = rig.shared.step
	local at: vector = vector.create(30, 0, 40)
	rig.workspace.CurrentCamera.CFrame = roblox.CFrame.new(30, step.standing / 2, 0)

	local function send(tick: number)
		rig.relay({
			tick = tick,
			reveals = { { slot = SLOT, generation = 1, kind = "Npc" } },
			records = { { slot = SLOT, generation = 1, position = at, word = rig.word({}) } },
		})
	end

	rig.slots({ { slot = SLOT, generation = 1, rig = "A" } })
	send(TICK)
	rig.frames(FRAMES)

	local _, box: any, label: any = rig.slot(SLOT)
	if not box then
		return false, "The slot's record drew no box"
	end

	local live: any = box.Color3
	if label.TextColor3 ~= live then
		return false, "A fresh record's label and box differ in color"
	elseif not string.find(label.Text, DISTANCE, 1, true) then
		return false, `The label reads "{label.Text}", not the {DISTANCE} from the camera`
	end

	task.wait(STALE + MARGIN)
	rig.frames(FRAMES)

	local age: number? = tonumber(label.Text:match(AGE))
	if box.Color3 == live or label.TextColor3 ~= box.Color3 then
		return false, `A record {STALE + MARGIN} s old left the box in its fresh color`
	elseif age == nil or age < STALE then
		return false, `The label reads "{label.Text}", not an age past {STALE} s`
	end

	send(TICK + 1)
	rig.frames(FRAMES)

	if box.Color3 ~= live or label.TextColor3 ~= live then
		return false, "A new record left the box greyed"
	end

	switch(false)

	return true, nil
end
