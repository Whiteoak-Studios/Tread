--[[
    A render time between two samples answers the place, yaw and shapes
    between them, with the earlier posture held until the next sample's
    tick, and one exactly on a sample answers that sample
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 12
local LEGS_BOTTOM: number = 0.4 -- The standing legs' bottom in the example's hit shapes, below its waist
local NEAR: number = 1e-9

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()
	state.position = vector.create(10.5, 4, -2)
	state.facing = 0
	History.write(SLOT, 20, state, 0)

	state.position = vector.create(12.5, 5, -6)
	state.facing = math.pi / 2
	state.posture = "Crouch"
	History.write(SLOT, 21, state, 0)

	local quarter = History.sampleAt(SLOT, 20.25)
	local want: vector = vector.create(11, 4.25, -3)
	if quarter == nil or quarter.position ~= want then
		return false, `A quarter of the way between the samples read {quarter and quarter.position}, not {want}`
	elseif math.abs(quarter.yaw - math.pi / 8) > NEAR then
		return false, `A quarter of the way between yaws 0 and 90° read a yaw of {quarter.yaw}, not π/8`
	elseif quarter.posture ~= "Stand" then
		return false, `Before the crouched sample's tick the posture read {quarter.posture}, not the earlier Stand`
	end

	-- The standing legs' bottom, below the waist, moved with the feet
	local legs: vector = quarter.zones.legs.from
	local feetLegs: vector = want + vector.create(0, LEGS_BOTTOM, 0)
	if vector.magnitude(legs - feetLegs) > NEAR then
		return false, `Between the samples the legs' bottom sat at {legs}, not at {feetLegs}`
	end

	local late = History.sampleAt(SLOT, 20.75)
	if late == nil or late.posture ~= "Stand" then
		return false, `Three quarters of the way the posture read {late and late.posture}, not the earlier Stand`
	end

	local on = History.sampleAt(SLOT, 20)
	if on == nil or on.position ~= vector.create(10.5, 4, -2) or on.yaw ~= 0 then
		return false, `Exactly on the first sample read {on and on.position}, yaw {on and on.yaw}`
	end

	local second = History.sampleAt(SLOT, 21)
	if second == nil or second.position ~= vector.create(12.5, 5, -6) or second.posture ~= "Crouch" then
		return false, `Exactly on the second sample read {second and second.position}, {second and second.posture}`
	end

	return true, nil
end
