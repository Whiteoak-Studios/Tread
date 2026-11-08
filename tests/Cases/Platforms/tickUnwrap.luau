--[[
    Platforms.tick unwraps the world's u16 tick against its clock, the
    shorter way round the wrap, ahead of the clock and behind it, across
    the wrap and far past the first, so a path always runs on the server's
    tick counted from its start
--]]

--!strict
local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local WRAP: number = 2 ^ 16

-- Each clock, the tick it reads, and the unwrapped tick it must give
local CASES: { { clock: number, tick: number, unwrapped: number } } = {
	{ clock = 0, tick = 0, unwrapped = 0 },
	{ clock = 100, tick = 130, unwrapped = 130 },
	{ clock = 100, tick = 90, unwrapped = 90 },
	{ clock = 65530, tick = 65535, unwrapped = 65535 },
	{ clock = 65530, tick = 3, unwrapped = 65539 }, -- Across the wrap ahead of the clock
	{ clock = 65539, tick = 65530, unwrapped = 65530 }, -- And back across it behind the clock
	{ clock = 200000, tick = 200000 % WRAP, unwrapped = 200000 },
	{ clock = 200000, tick = (200000 + 32767) % WRAP, unwrapped = 200000 + 32767 }, -- The farthest ahead it reaches
	{ clock = 200000, tick = (200000 - 32768) % WRAP, unwrapped = 200000 - 32768 }, -- And behind
}

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local world: any = Riders.world()

	for _, case in CASES do
		world.clock = case.clock
		world.tick = case.tick

		local unwrapped: number = Platforms.tick(world)
		if unwrapped ~= case.unwrapped then
			return false, `The clock {case.clock} read the tick {case.tick} as {unwrapped}, not {case.unwrapped}`
		end
	end

	return true, nil
end
