--[[
    Tick.start refuses an early part that is no function, a second stage
    with one, and one on a between stage, each naming the stage it refused
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2

type Refused = { what: string, stages: { { [string]: any } }, says: string }

local function run(_: number) end

-- Each list of stages Tick.start must refuse, what it shows, and the refusal's words
local REFUSED: { Refused } = {
	{
		what = "an early part that is a string",
		stages = { { name = "bad", run = run, early = "a part" } },
		says = "Tick.start takes the stage bad's early as a function or nil, not a string",
	},
	{
		what = "a second stage with an early part",
		stages = { { name = "first", run = run, early = run }, { name = "second", run = run, early = run } },
		says = "Tick.start takes an early part on one stage at most, and second is a second",
	},
	{
		what = "an early part on a between stage",
		stages = { { name = "slices", between = true, run = run, early = run } },
		says = "Tick.start takes no early part on a between stage, as slices is",
	},
}

return function (): (boolean, string | nil)
	for _, refused: Refused in REFUSED do
		local globals: any = Environment.load(GLOBALS)
		Frames.new(globals)
		local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

		local started: boolean, message: any = pcall(Tick.start, RATE, CATCH_UP, refused.stages)
		if started or not string.find(tostring(message), refused.says, 1, true) then
			return false, `Tick.start given {refused.what} was not refused as "{refused.says}": {message}`
		end
	end

	return true, nil
end
