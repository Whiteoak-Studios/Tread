--[[
    The server's check takes the four frame caps left out or well formed,
    refuses each wrong one with its full message, and Config.underLoad, the
    relay's seam, answers tiers.underLoad as the server's check does
--]]

--!strict
local Environment = require("../../Environment")

local CONFIG: string = "src/Config.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local NUDGE: number = 0.01 -- How far past or short of an edge a value is moved
local RELAY_BUDGET: number = 0.005 -- Seconds, the dev place's relay budget

-- What each refusal says it expected, as Config words it
local BOOLEAN: string = "true or false"
local SECONDS: string = "a number of 0 or more"
local RUNS: string = "a whole number of 1 or more"
local SCALE: string = "a number above 0 and at most 1"
local TABLE: string = "a table"
local NO_KEY: string = "no value, since Tread reads no such key"
local NEEDS_BUDGET: string = `{SECONDS}, since server.tiers.underLoad is given`

-- A dotted path under the server settings and the value set there, nil to remove the key
type Edit = { path: string, value: any }

-- The edits made to the example's server settings, and the whole refusal the checks give, or none where they take
-- them; seam also judges Config.underLoad on the edited tiers.underLoad
type Case = { edits: { Edit }, refusal: string?, seam: boolean? }

-- The message a check refuses a key with
local function refusal(path: string, expected: string, got: string): string
	return `{path} expected {expected}, and got {got}`
end

-- One key set, refused as the message gives it, or taken with none
local function one(path: string, value: any, message: string?): Case
	return { edits = { { path = path, value = value } }, refusal = message }
end

-- A far rate under load with the dev place's relay budget beside it, judged by the seam too
local function far(underLoad: any, message: string?): Case
	return {
		edits = { { path = "relay.budget", value = RELAY_BUDGET }, { path = "tiers.underLoad", value = underLoad } },
		refusal = message,
		seam = true,
	}
end

-- Why a check's answer on a call is wrong, or nil when it refused with the whole message, or took it with none
local function judge(check: (...any) -> (), message: string?, ...: any): string?
	local passed: boolean, failure: any = pcall(check, ...)
	if message == nil then
		if not passed then
			return `it was refused as "{failure}"`
		end

		return nil
	elseif passed then
		return `it was taken, where "{message}" was due`
	elseif tostring(failure) ~= message then
		return `it was refused as "{failure}", where "{message}" was due`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Config = Environment.load(CONFIG)
	local Example = Environment.load(EXAMPLE)
	local huge: string = tostring(math.huge)
	local nan: number = 0 / 0

	-- 1) Every cap left out, the server's check takes the tables as the example gives them
	local plain: boolean, failure: any = pcall(Config.server, Example.shared(), Example.server())
	if not plain then
		return false, `The example's tables with no frame cap were refused: {failure}`
	end

	local cases: { Case } = {
		-- 2) Each cap well formed: both answers of antiEsp.whole, each budget at 0 and at the dev place's value, the
		-- relay table holding the budget alone, the far rate at the dev place's values and its edges, and all four
		one("antiEsp.whole", true),
		one("antiEsp.whole", false),
		one("npcs.budget", 0),
		one("npcs.budget", 0.001),
		one("relay.budget", 0),
		one("relay.budget", RELAY_BUDGET),
		one("relay", { budget = RELAY_BUDGET }),
		far({ runs = 20, scale = 0.5 }),
		far({ runs = 1, scale = 1 }),
		far({ runs = 1, scale = NUDGE }),
		{
			edits = {
				{ path = "antiEsp.whole", value = true },
				{ path = "npcs.budget", value = 0.001 },
				{ path = "relay.budget", value = RELAY_BUDGET },
				{ path = "tiers.underLoad", value = { runs = 20, scale = 0.5 } },
			},
		},

		-- 3) Each wrong value of a cap, refused by its path with what it expected and what it got
		one("antiEsp.whole", "true", refusal("server.antiEsp.whole", BOOLEAN, `"true"`)),
		one("antiEsp.whole", 1, refusal("server.antiEsp.whole", BOOLEAN, "1")),
		one("npcs.budget", -NUDGE, refusal("server.npcs.budget", SECONDS, tostring(-NUDGE))),
		one("npcs.budget", math.huge, refusal("server.npcs.budget", SECONDS, huge)),
		one("npcs.budget", nan, refusal("server.npcs.budget", SECONDS, tostring(nan))),
		one("npcs.budget", "0.001", refusal("server.npcs.budget", SECONDS, `"0.001"`)),
		one("relay.budget", -1, refusal("server.relay.budget", SECONDS, "-1")),
		one("relay.budget", math.huge, refusal("server.relay.budget", SECONDS, huge)),
		one("relay.budget", "0.005", refusal("server.relay.budget", SECONDS, `"0.005"`)),
		far(20, refusal("server.tiers.underLoad", TABLE, "20")),
		far({ scale = 0.5 }, refusal("server.tiers.underLoad.runs", RUNS, "nil")),
		far({ runs = 0, scale = 0.5 }, refusal("server.tiers.underLoad.runs", RUNS, "0")),
		far({ runs = 1.5, scale = 0.5 }, refusal("server.tiers.underLoad.runs", RUNS, "1.5")),
		far({ runs = -1, scale = 0.5 }, refusal("server.tiers.underLoad.runs", RUNS, "-1")),
		far({ runs = math.huge, scale = 0.5 }, refusal("server.tiers.underLoad.runs", RUNS, huge)),
		far({ runs = 20 }, refusal("server.tiers.underLoad.scale", SCALE, "nil")),
		far({ runs = 20, scale = 0 }, refusal("server.tiers.underLoad.scale", SCALE, "0")),
		far({ runs = 20, scale = 1 + NUDGE }, refusal("server.tiers.underLoad.scale", SCALE, tostring(1 + NUDGE))),
		far({ runs = 20, scale = -0.5 }, refusal("server.tiers.underLoad.scale", SCALE, "-0.5")),
		far({ runs = 20, scale = nan }, refusal("server.tiers.underLoad.scale", SCALE, tostring(nan))),
		far({ runs = 20, scale = "0.5" }, refusal("server.tiers.underLoad.scale", SCALE, `"0.5"`)),
		far({ runs = 20, scale = 0.5, extra = 1 }, refusal("server.tiers.underLoad.extra", NO_KEY, "1")),

		-- 4) The far rate under load with no relay budget, the relay table holding none or left out
		one("tiers.underLoad", { runs = 20, scale = 0.5 }, refusal("server.relay.budget", NEEDS_BUDGET, "nil")),
		{
			edits = {
				{ path = "relay", value = nil },
				{ path = "tiers.underLoad", value = { runs = 20, scale = 0.5 } },
			},
			refusal = refusal("server.relay.budget", NEEDS_BUDGET, "nil"),
		},
	}

	for index: number, case: Case in cases do
		local server: any = Example.server()
		for _, edit: Edit in case.edits do
			Example.set(server, edit.path, edit.value)
		end

		local problem: string? = judge(Config.server, case.refusal, Example.shared(), server)
		if problem then
			return false, `Case {index}, the server's check: {problem}`
		end

		if case.seam then
			local seam: string? = judge(Config.underLoad, case.refusal, server.tiers.underLoad)
			if seam then
				return false, `Case {index}, Config.underLoad: {seam}`
			end
		end
	end

	-- 5) The seam takes a well-formed far rate on its own, since only the server's check sees the relay table
	local seamProblem: string? = judge(Config.underLoad, nil, { runs = 20, scale = 0.5 })
	if seamProblem then
		return false, `Config.underLoad with no relay budget beside it: {seamProblem}`
	end

	return true, nil
end
