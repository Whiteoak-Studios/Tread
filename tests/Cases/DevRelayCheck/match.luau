--[[
    The relay check's layouts under the dev place's crowd cap, run through a
    serial copy and a copy on two stand-in workers, match on every run and
    reach every part they are for, the cap holding players out in the crowd
--]]

--!strict
local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevServer/Harness")
local StandIn = require("../../Fixtures/Relay/StandIn")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local WORKERS: number = 2
local TIMEOUT: number = 1
local LEAST_RUNS: number = 20

-- The dev place's crowd cap, which the live check runs every layout under, so a layout of more viewers than its size
-- plus one is the one where it holds players out
local CROWD: { size: number, rate: number, floor: number } = { size = 32, rate = 20, floor = 5 }

-- The relay members a layout must call between runs
local MEMBERS: { string } = { "setLook", "setInvisible", "shotNear", "reveal", "revealAll", "setDistance", "remove" }

-- One copy of the relay's modules, from an environment of its own
local function copyOf(globals: any): any
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread

	return {
		Relay = globals.require(tread.Server.Relay),
		Slots = globals.require(tread.Server.Slots),
		Taps = globals.require(tread.Server.Taps),
		State = globals.require(tread.Step.State),
		Fields = globals.require(tread.Codec.Fields),
		Constants = globals.require(tread.Constants),
		Sequence = globals.require(tread.Codec.Sequence),
		Block = globals.require(tread.Codec.Block),
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local server: any = loaded.game:GetService("ServerScriptService").Server
	local RelayCheck: any = loaded.require(server.RelayCheck)
	local config: any = loaded.require(server.Config.RelayCheck)

	for _, name: string in config.order do
		local plan: any = RelayCheck.plan(name)

		-- 1) The plan: long enough, with a leave and a rejoin after it
		local left: number? = nil
		local back: number? = nil
		for run: number = 1, plan.layout.runs do
			for _, step: any in plan.after[run] or {} do
				if step.event == "leave" then
					left = run
				end
			end

			for _, step: any in plan.before[run] or {} do
				if step.event == "rejoin" then
					back = run
				end
			end
		end

		if plan.layout.runs < LEAST_RUNS then
			return false, `The {name} layout runs {plan.layout.runs} times, under {LEAST_RUNS}`
		elseif not (left and back and back > left) then
			return false, `The {name} layout has no viewer leaving and rejoining after`
		end

		-- 2) Both copies, each in an environment of its own, the second's relay making its workers in a stand-in pool
		local pool: { [string]: any } = {}
		function pool.new(count: number, poolName: string, remote: any, settings: any): any
			local made: any = StandIn.new(count, poolName, remote, settings)
			pool.made = made

			return made
		end

		local serialGlobals: any = Environment.load(GLOBALS)
		local serial: any = copyOf(serialGlobals)
		local workers: any = copyOf(Environment.load(GLOBALS, { [POOL] = pool }))
		local Example: any =
			serialGlobals.require(serialGlobals.game:GetService("ServerScriptService").Fixtures.Config.Example)

		local tables: any = Example.server()
		tables.tiers.crowd = CROWD

		local summary: any = RelayCheck.check(plan, serial, workers, {
			shared = Example.shared(),
			server = tables,
			workers = WORKERS,
			timeout = TIMEOUT,
			started = function () end,
		}, function ()
			pool.made:deliver()
		end)

		-- 3) Every run matched, and the runs reached what the check is for
		if summary.found ~= 0 then
			return false,
				`The {name} layout found {summary.found} mismatches: {table.concat(summary.mismatches, " | ")}`
		elseif summary.runs ~= plan.layout.runs then
			return false, `The {name} layout ran {summary.runs} of its {plan.layout.runs} runs`
		elseif summary.reveals == 0 or summary.hides == 0 or summary.frames == 0 or summary.asks == 0 then
			local reached: string = `{summary.reveals} reveals, {summary.hides} hides, {summary.frames} frames`
			return false, `The {name} layout reached {reached} and {summary.asks} asks`
		elseif plan.moderator and summary.withheld == 0 then
			return false, `The {name} layout's moderator was sent no withheld block`
		elseif (plan.layout.viewers - 1 > CROWD.size) ~= (summary.held > 0) then
			return false, `The {name} layout of {plan.layout.viewers} viewers held {summary.held} outside the cap`
		end

		for _, member: string in MEMBERS do
			if not summary.calls[member] then
				return false, `The {name} layout made no {member} call between runs`
			end
		end
	end

	return true, nil
end
