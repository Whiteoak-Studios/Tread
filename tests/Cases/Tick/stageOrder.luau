--[[
    The tick runs its stages in the order given, a stage added after one
    runs straight after it and before whatever followed, one added after the
    last runs last; addStage before the start, after a stage that is none,
    with a name taken or with no function is refused, and so is a second start
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local Tick: any = globals.require(globals.game:GetService("ReplicatedStorage").Packages.Tread.Server.Tick)

	local order: { string } = {}
	local function stage(name: string): { name: string, run: (tick: number) -> () }
		return {
			name = name,
			run = function (_: number)
				table.insert(order, name)
			end,
		}
	end

	if pcall(Tick.addStage, "early", "a", stage("early").run) then
		return false, "addStage took a stage before the tick started"
	elseif pcall(Tick.start, 0, CATCH_UP, {}) or pcall(Tick.start, RATE, 0, {}) then
		return false, "Tick.start took a rate or a catch-up of 0"
	end

	Tick.start(RATE, CATCH_UP, { stage("a"), stage("b"), stage("c") })
	Tick.addStage("x", "a", stage("x").run)
	Tick.addStage("y", "c", stage("y").run)

	frames:run(1 / RATE)

	if table.concat(order, ",") ~= "a,x,b,c,y" then
		return false, `One tick ran {table.concat(order, ", ")}, not a, x, b, c, y`
	end

	local refusals: { { name: string, args: { any } } } = {
		{ name = "a stage after one that is none", args = { "z", "none", stage("z").run } },
		{ name = "a second stage named b", args = { "b", "c", stage("b").run } },
		{ name = "a run that is no function", args = { "w", "a", 5 } },
		{ name = "an empty name", args = { "", "a", stage("").run } },
	}

	for _, refusal in refusals do
		if pcall(Tick.addStage, table.unpack(refusal.args)) then
			return false, `addStage took {refusal.name}`
		end
	end

	if pcall(Tick.start, RATE, CATCH_UP, {}) then
		return false, "Tick.start ran a second time"
	end

	return true, nil
end
