--[[
    Both entry points' checks refuse a shared table with a key missing,
    of the wrong kind, out of its range or unknown, naming the first such
    key by its full path, and refuse collision functions given in part
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"

type Refusal = {
	path: string, -- The key the case breaks
	value: any,
	names: string?, -- The key the refusal must name, when it isn't the one broken
}

local REFUSALS: { Refusal } = {
	{ path = "step.walk", value = nil },
	{ path = "step.walk", value = "10" },
	{ path = "step", value = nil },
	{ path = "step", value = 5 },
	{ path = "step.walks", value = 10 },
	{ path = "steps", value = {} },
	{ path = "rates.simulation", value = 0 },
	{ path = "rates.relay", value = -20 },
	{ path = "ticks.ahead", value = 2.5 },
	{ path = "ticks.debt", value = -1 },
	{ path = "ticks.nudge", value = 1.5 },
	{ path = "step.gravity", value = 0 / 0 },
	{ path = "step.gravity", value = math.huge },
	{ path = "step.walkable", value = 1.2 },
	{ path = "step.waterEntry", value = -0.1 },
	{ path = "step.leanShift", value = 0.57 },
	{ path = "step.lyingBox.lift", value = -1 },
	{ path = "step.lyingBox.depth", value = 1 },
	{ path = "tolerances.Ground", value = 1.5 },
	{ path = "tolerances.Mantle", value = -1 },
	{ path = "tolerances.Rider", value = nil },
	{ path = "hitShapes.Crouch", value = nil },
	{ path = "hitShapes.Prone", value = {} },
	{ path = "hitShapes.Stand.body.radius", value = 0 },
	{ path = "hitShapes.Stand.zones.head.from", value = 1 },
	{ path = "hitShapes.Stand.zones.head", value = "head" },
	{ path = "hitShapes.Downed.waist", value = "0.6" },
	{ path = "collision.sphere", value = nil },
	{ path = "collision.ray", value = 5 },
	{ path = "collision", value = {}, names = "collision.include" },
	{ path = "collision.include", value = { 5 }, names = "collision.include[1]" },
	{ path = "collision.cast", value = print },
	{ path = "water", value = 0 },
	{ path = "rules", value = nil },
	{ path = "fields.held", value = nil },
	{ path = "fields.command", value = "slot" },
	{ path = "fields.extra", value = {} },
}

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)

	for _, refusal: Refusal in REFUSALS do
		local path: string = `shared.{refusal.names or refusal.path}`

		local shared = Example.shared()
		Example.set(shared, refusal.path, refusal.value)

		local problem: string? = Example.refusal(Config.server, path, shared, Example.server())
			or Example.refusal(Config.client, path, shared, Example.client())
		if problem then
			return false, problem
		end
	end

	local missing: string? = Example.refusal(Config.server, "shared", nil, Example.server())
	if missing then
		return false, missing
	end

	-- With two keys wrong, the one first in key order is named: rates before step, and sprint before walk
	local twice = Example.shared()
	Example.set(twice, "step.walk", "10")
	Example.set(twice, "rates.relay", 0)

	local first: string? = Example.refusal(Config.server, "shared.rates.relay", twice, Example.server())
	if first then
		return false, first
	end

	local inStep = Example.shared()
	Example.set(inStep, "step.walk", "10")
	Example.set(inStep, "step.sprint", "18")

	local firstInStep: string? = Example.refusal(Config.server, "shared.step.sprint", inStep, Example.server())
	if firstInStep then
		return false, firstInStep
	end

	return true, nil
end
