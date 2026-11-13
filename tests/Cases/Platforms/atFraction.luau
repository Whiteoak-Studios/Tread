--[[
    Platforms.at places a platform on the 1/512 quantum at a whole tick,
    and between the two whole ticks around a fraction through Math.lerp of
    those two places, so a client drawing between ticks and the rewind
    place it alike
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"
local MATH: string = "src/Step/Math.luau"

local SLIDER: number = 9
local TICK: number = 1234
local FRACTIONS: { number } = { 0.25, 0.5, 0.875, 0.1 }

-- A path whose places fall off the quantum, a third of a stud along X and a seventh up each tick
local function slider(): { [string]: any }
	return {
		id = SLIDER,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.one } },
		path = function (tick: number, _: number?): any
			return roblox.Vector3.new(tick / 3, 1000 + tick / 7, -tick / 11)
		end,
	}
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local Math: any = Environment.load(MATH)
	local world: any = Riders.world()
	Platforms.add(world, slider())

	local whole: vector = Platforms.at(world, SLIDER, TICK)
	local following: vector = Platforms.at(world, SLIDER, TICK + 1)
	local exact: vector = vector.create(TICK / 3, 1000 + TICK / 7, -TICK / 11)
	local quantized: vector = vector.create(Math.quantize(exact.x), Math.quantize(exact.y), Math.quantize(exact.z))
	if whole ~= quantized then
		return false, `At tick {TICK} the platform stood at {whole}, not its path's place on the quantum, {quantized}`
	end

	for _, share: number in FRACTIONS do
		local between: vector = Platforms.at(world, SLIDER, TICK + share)
		local expected: vector = vector.create(
			Math.lerp(whole.x, following.x, share),
			Math.lerp(whole.y, following.y, share),
			Math.lerp(whole.z, following.z, share)
		)

		if between ~= expected then
			return false, `At tick {TICK + share} the platform stood at {between}, not {expected} between its ticks`
		end
	end

	-- A negative fraction's whole tick is the one below it
	local below: vector = Platforms.at(world, SLIDER, -0.5)
	local low: vector = Platforms.at(world, SLIDER, -1)
	local high: vector = Platforms.at(world, SLIDER, 0)
	local halfway: vector =
		vector.create(Math.lerp(low.x, high.x, 0.5), Math.lerp(low.y, high.y, 0.5), Math.lerp(low.z, high.z, 0.5))
	if below ~= halfway then
		return false, `At tick -0.5 the platform stood at {below}, not halfway between ticks -1 and 0`
	end

	return true, nil
end
