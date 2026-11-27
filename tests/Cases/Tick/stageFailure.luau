--[[
    A stage that throws loses its own work for the tick and is reported as
    stage with its name and no player, once a tick, while the stages before
    and after it and every later tick still run
--]]

--!strict
local Environment = require("../../Environment")
local Frames = require("../../Fixtures/Server/Frames")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local RATE: number = 20
local CATCH_UP: number = 2
local TICKS: number = 3

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local frames: Frames.Frames = Frames.new(globals)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Reports: any = globals.require(tread.Server.Reports)
	local Tick: any = globals.require(tread.Server.Tick)

	local reports: { { player: any, kind: string, measurement: any } } = {}
	Reports.connect(function (player: any, kind: string, measurement: any)
		table.insert(reports, { player = player, kind = kind, measurement = measurement })
	end)

	local ran: { [string]: number } = { before = 0, after = 0 }

	Tick.start(RATE, CATCH_UP, {
		{
			name = "before",
			run = function (_: number)
				ran.before += 1
			end,
		},
		{
			name = "broken",
			run = function (_: number)
				error("This stage throws on purpose, to show the tick goes on")
			end,
		},
		{
			name = "after",
			run = function (_: number)
				ran.after += 1
			end,
		},
	})

	for _ = 1, TICKS do
		frames:run(1 / RATE)
	end

	if ran.before ~= TICKS or ran.after ~= TICKS then
		return false, `Over {TICKS} ticks the stages ran {ran.before} and {ran.after} times around the broken one`
	elseif #reports ~= TICKS then
		return false, `The broken stage gave {#reports} reports over {TICKS} ticks`
	end

	for _, report in reports do
		if report.kind ~= "stage" or report.measurement ~= "broken" or report.player ~= nil then
			return false, `The broken stage was reported as {report.kind} {report.measurement}`
		end
	end

	local run: number = Tick.counts()
	if run ~= TICKS then
		return false, `The tick counted {run} ticks run, not {TICKS}`
	end

	return true, nil
end
