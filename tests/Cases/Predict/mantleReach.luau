--[[
    Predict.mantle runs the press's own search, so it follows the game's
    mantle reach: a face 1.2 studs past the hull gives a point at a reach
    of 1.39 and none at 1.0
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/Predict/Harness")

local SLIDES: string = "tests/Fixtures/Step/Slides.luau"
local GAP: number = 1.2 -- Studs from the hull's front to the shelf's face
local REACH: number = 1.39
local SHORT: number = 1
local DEPTH: number = 1 -- The spawn OwnerState's queue, inside the band

-- Whether Predict, given a reach, gives a point for a body the gap from the shelf's face
local function found(Slides: any, reach: number): (boolean, any)
	local settings: any = Slides.settings()
	settings.mantleReach = reach

	local rig: any = Harness.new({ step = settings, parts = Slides.parts })
	local shelf: any = Slides.shelf
	local face: number = shelf.center.z + shelf.size.z / 2
	local state: any = Slides.state(vector.create(shelf.center.x, Slides.resting, face + settings.radius + GAP), true)
	state.tick = 100
	state.fields = { beingRevived = false }
	state.block = { sinceJump = 0, sinceShot = 15 }

	rig.Predict.receive(rig.owner(state, DEPTH))
	local point: any = rig.Predict.mantle()

	return point ~= nil, point
end

return function (): (boolean, string | nil)
	local Slides: any = Environment.load(SLIDES)

	local reached: boolean, point: any = found(Slides, REACH)
	if not reached then
		return false, `Predict.mantle at a reach of {REACH} gave no point for a face {GAP} studs past the hull`
	end

	local shortReached: boolean, shortPoint: any = found(Slides, SHORT)
	if shortReached then
		return false, `Predict.mantle at a reach of {SHORT} gave {shortPoint} for a face {GAP} studs past the hull`
	end

	return point ~= nil, nil
end
