--[[
    A called path runs from the call's tick on the ticks from it on, and
    from the call before it on the earlier ticks, with no call before both;
    a newer call pushes the oldest out, an older one fills the place of the
    one before, a repeat changes nothing, and a ride feels a call at once
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local RIDERS: string = "tests/Fixtures/Step/RiderParity.luau"
local PLATFORMS: string = "src/Step/Platforms.luau"

local CAR: number = 12
local NONE: number = -1 -- The height the path stands at with no call to run from
local BASE_X: number = 200

-- A car whose height is the call it runs from, so each place names the call that served it
local function car(): { [string]: any }
	return {
		id = CAR,
		boxes = { { center = roblox.Vector3.new(0, -0.5, 0), size = roblox.Vector3.new(10, 1, 10) } },
		path = function (_: number, calledAt: number?): any
			return roblox.Vector3.new(BASE_X, calledAt or NONE, 0)
		end,
	}
end

-- Why the call serving each tick was not the one expected, or nil
local function serves(Platforms: any, world: any, expected: { [number]: number }): string?
	for tick: number, call: number in expected do
		local at: vector? = Platforms.at(world, CAR, tick)
		if not at or at.y ~= call then
			return `tick {tick} ran from {at and at.y}, where {call} was expected`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local Riders: any = Environment.load(RIDERS)
	local Platforms: any = Environment.load(PLATFORMS)
	local world: any = Riders.world()
	Platforms.add(world, car())
	local entry: any = world.platforms[CAR]

	local uncalled: string? = serves(Platforms, world, { [0] = NONE, [500] = NONE })
	if uncalled then
		return false, `Before any call, {uncalled}`
	end

	Platforms.call(world, CAR, 100)
	local once: string? = serves(Platforms, world, { [99] = NONE, [100] = 100, [150] = 100 })
	if once then
		return false, `After a call on tick 100, {once}`
	end

	Platforms.call(world, CAR, 200)
	local twice: string? = serves(Platforms, world, { [90] = NONE, [150] = 100, [199] = 100, [200] = 200, [250] = 200 })
	if twice then
		return false, `After calls on ticks 100 and 200, {twice}`
	elseif entry.calledAt ~= 200 or entry.calledBefore ~= 100 then
		return false, `The entry kept the calls {entry.calledAt} and {entry.calledBefore}, not 200 and 100`
	end

	-- A third pushes the oldest out, so the ticks it served have no call to run from
	Platforms.call(world, CAR, 300)
	local thrice: string? = serves(Platforms, world, { [150] = NONE, [250] = 200, [300] = 300 })
	if thrice then
		return false, `After a third call on tick 300, {thrice}`
	end

	-- A call older than the latest but newer than the one before takes the older place; a repeat, or an older one
	-- still, changes nothing
	Platforms.call(world, CAR, 260)
	Platforms.call(world, CAR, 300)
	Platforms.call(world, CAR, 150)
	if entry.calledAt ~= 300 or entry.calledBefore ~= 260 then
		return false, `After calls on 260, 300 again and 150, the entry kept {entry.calledAt} and {entry.calledBefore}`
	end

	-- A call forgets the place the step kept for its tick, and a rider rides a call on the tick after the last run,
	-- as the server makes one
	world.clock = 400
	local body: any = Riders.standOn(world, CAR, 400, 0, 0)
	local command: any = Riders.command()
	Riders.step(body, command, world, 400)

	local kept: vector = Platforms.at(world, CAR, 400)
	local recalled: any = Riders.world()
	Platforms.add(recalled, car())
	recalled.clock = 400
	Riders.step(Riders.standOn(recalled, CAR, 400, 0, 0), command, recalled, 400)
	Platforms.call(recalled, CAR, 400)
	if kept.y ~= 300 or Platforms.at(recalled, CAR, 400).y ~= 400 then
		return false, `A call on a tick the step had placed the car for left it at {Platforms.at(recalled, CAR, 400)}`
	end

	Platforms.call(world, CAR, 401)
	Riders.step(body, command, world, 401)
	local offset: vector = body.position - Platforms.at(world, CAR, 401)
	if Platforms.at(world, CAR, 401).y ~= 401 or body.platform ~= CAR then
		return false,
			`The call on tick 401 left the car at {Platforms.at(world, CAR, 401)} with its rider on {body.platform}`
	elseif offset.y ~= Riders.standOn(world, CAR, 401, 0, 0).position.y - 401 then
		return false, `The rider stood {offset} from the car after its call, not a skin over its top`
	end

	return true, nil
end
