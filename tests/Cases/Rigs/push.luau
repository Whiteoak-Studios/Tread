--[[
    A dying torso's push runs along the attack's direction raised by the up
    bias at the push speed, whatever the direction's length, and a death
    with no direction pushes nothing
--]]

--!strict
local Environment = require("../../Environment")

local RAGDOLL: string = "src/Client/Rigs/Ragdoll.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"

local TOLERANCE: number = 1e-6

local function near(a: vector, b: vector): boolean
	return vector.magnitude(a - b) < TOLERANCE
end

return function (): (boolean, string | nil)
	local Ragdoll = Environment.load(RAGDOLL)
	local bodies = Environment.load(RIG).bodies

	-- Along X raised by 0.5 is (1, 0.5, 0), whose length is sqrt(1.25), so 6 studs a second along it
	local expected: vector = vector.create(1, bodies.pushUpBias, 0) / math.sqrt(1.25) * bodies.pushSpeed

	local unit: vector = Ragdoll.push(vector.create(1, 0, 0), bodies)
	if not near(unit, expected) then
		return false, `A push along X gave {unit}, not {expected}`
	end

	local long: vector = Ragdoll.push(vector.create(5, 0, 0), bodies)
	if not near(long, expected) then
		return false, `A push along a longer X gave {long}, not the unit direction's {expected}`
	end

	if math.abs(vector.magnitude(unit) - bodies.pushSpeed) > TOLERANCE then
		return false, `A push moved at {vector.magnitude(unit)} studs a second, not {bodies.pushSpeed}`
	end

	local none: vector = Ragdoll.push(nil, bodies)
	local zero: vector = Ragdoll.push(vector.zero, bodies)
	if none ~= vector.zero or zero ~= vector.zero then
		return false, `A death with no direction pushed {none}, and one with a zero direction {zero}`
	end

	return true, nil
end
