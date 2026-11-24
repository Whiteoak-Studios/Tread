--[[
    Relay.setBudget and Relay.budget: refused before start and for anything
    but a finite number of 0 or more or nil, nil refused while the far rate
    under load is set, and a budget set or taken off while a round is out on
    a stand-in worker leaving that round neither measured nor judged
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SECONDS: number = 0.005
local BUDGET: number = 1 -- Stand-in seconds
local STEP: number = 2 -- Stand-in seconds a read moves on, so a run with workers measures 4 and passes the budget
local UNDER_LOAD: { runs: number, scale: number } = { runs = 2, scale = 0.5 }
local REFUSED: string = "Relay.setBudget takes seconds" -- How a value that is no budget is refused
local PLAIN: boolean = true -- string.find's flag that matches the text as it is, with no pattern

-- Whether a call errors with text that starts as given
local function refuses(text: string, call: (...any) -> ...any, ...: any): boolean
	local ran: boolean, failure: any = pcall(call, ...)

	return not ran and string.find(tostring(failure), text, 1, PLAIN) ~= nil
end

local function none() end

return function (): (boolean, string | nil)
	-- A relay never started refuses both seams, and a start whose passed port or clock is no function
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local unstarted: any = globals.require(tread.Server.Relay)
	if not refuses("Relay.setBudget ran before Relay.start", unstarted.setBudget, SECONDS) then
		return false, "Relay.setBudget ran on a relay never started"
	elseif not refuses("Relay.setUnderLoad ran before Relay.start", unstarted.setUnderLoad, UNDER_LOAD) then
		return false, "Relay.setUnderLoad ran on a relay never started"
	elseif
		not refuses("Relay.start takes anti-ESP's passed", unstarted.start, {}, none, none, none, none, nil, nil, 5)
	then
		return false, "Relay.start took a passed port that is no function"
	elseif not refuses("Relay.start takes its clock", unstarted.start, { clock = 5 }, none, none, none, none) then
		return false, "Relay.start took a clock that is no function"
	end

	local Harness: any = Layouts.harness()
	local harness: any = Harness.new(nil, nil, 1)
	local Relay: any = Harness.Relay
	local client: any = harness:viewer("Viewer")
	client.viewer.position = vector.zero
	harness:spawn("Player", vector.create(0, 0, -60))

	if Relay.budget() ~= nil then
		return false, `Relay.budget gave {Relay.budget()} before any was set`
	end

	Relay.setBudget(SECONDS)
	for _, value: any in { -1, 0 / 0, math.huge, -math.huge, "5", true, {} } do
		if not refuses(REFUSED, Relay.setBudget, value) then
			return false, `Relay.setBudget took {value}`
		elseif Relay.budget() ~= SECONDS then
			return false, `A refused Relay.setBudget({value}) left the budget at {Relay.budget()}`
		end
	end

	Relay.setBudget(0)
	if Relay.budget() ~= 0 then
		return false, `Relay.setBudget(0) left the budget at {Relay.budget()}`
	end

	-- Nil is refused while the far rate under load needs the budget, and taken once that is off
	Relay.setUnderLoad(UNDER_LOAD)
	if not refuses("Relay.setBudget takes nil only", Relay.setBudget, nil) or Relay.budget() ~= 0 then
		return false, "Relay.setBudget(nil) took the budget off under the far rate under load"
	end

	Relay.setUnderLoad(nil)
	Relay.setBudget(nil)
	if Relay.budget() ~= nil then
		return false, `Relay.setBudget(nil) left the budget at {Relay.budget()}`
	end

	harness.step = STEP

	-- A round out with no budget, which one set meanwhile never judges, and the next run reads the clock
	local function dispatch()
		harness.tick += 1
		Relay.run(harness.tick, harness.viewers, harness.states, harness.commands, harness.platforms)
	end

	dispatch()
	local before: number = harness.reads
	Relay.setBudget(BUDGET)
	harness.pool:deliver()
	if not Relay.finish() then
		return false, "The round set a budget while out never came in"
	end

	local _, over: number = Relay.caps()
	if harness.reads ~= before or over ~= 0 then
		return false,
			`A round begun with no budget read the clock {harness.reads - before} times and judged {over} over`
	end

	-- A round out under the budget, taken off meanwhile, is neither measured nor judged, and the next run reads nothing
	dispatch()
	before = harness.reads
	Relay.setBudget(nil)
	harness.pool:deliver()
	Relay.finish()

	_, over = Relay.caps()
	if harness.reads ~= before or over ~= 0 then
		return false,
			`A round begun under a budget taken off since read the clock {harness.reads - before} times at its finish and judged {over} over, not 0 and 0`
	end

	before = harness.reads
	harness:run()
	if harness.reads ~= before then
		return false, `A run with the budget off read the clock {harness.reads - before} times`
	end

	return true, nil
end
