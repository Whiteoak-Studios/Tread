--[[
    Verdict memory's switch refuses a call before anti-ESP starts and any
    value but true or false, changing nothing, and start refuses an occluder
    that is neither a function nor nil
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local ANTI_ESP: string = "src/Server/AntiEsp.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local SWITCHES: { boolean } = { true, false }
local STATES: { boolean } = { false, true } -- Memory off, then on, as each refusal must leave it
local NOT_FUNCTIONS: { any } = { "boxes", true, false, 0, {} } -- Occluders that are neither a function nor nil
local NOT_BOOLEANS: { any } = { "on", 1, 0, {} } -- Switches that are neither true nor false, nil aside
local ON: boolean = true -- Verdict memory's switch

local function blocked(_: vector, _: vector): boolean
	return false
end

return function (): (boolean, string | nil)
	local AntiEsp: any = Environment.load(ANTI_ESP)

	-- 1) Either way round before start
	for _, on: boolean in SWITCHES do
		local refused: boolean, why: string = Refuses("useMemory ran before AntiEsp.start", AntiEsp.useMemory, on)
		if not refused then
			return false, `AntiEsp.useMemory({on}) before start went another way: {why}`
		end
	end

	-- 2) An occluder that is neither a function nor nil, each start failing before it starts anything
	local Example: any = Environment.load(EXAMPLE)
	local settings: any = { shared = Example.shared(), server = Example.server() }

	for _, occluder: any in NOT_FUNCTIONS do
		local refused: boolean, why: string = Refuses(
			"occluder as a function or nil",
			AntiEsp.start,
			settings,
			{},
			{},
			blocked,
			occluder
		)
		if not refused then
			return false, `AntiEsp.start with an occluder of {occluder} went another way: {why}`
		end
	end

	-- So no refused start left anti-ESP started for the switch
	local still: boolean, stillWhy: string = Refuses("useMemory ran before AntiEsp.start", AntiEsp.useMemory, ON)
	if not still then
		return false, `AntiEsp.useMemory after the refused starts went another way: {stillWhy}`
	end

	-- 3) Started, every switch but true or false is refused, nil among them, leaving memory as it was, off then on
	local Harness: any = Environment.load(HARNESS)
	Harness.new()
	local started: any = Harness.AntiEsp

	for _, on: boolean in STATES do
		started.useMemory(on)

		for _, value: any in NOT_BOOLEANS do
			local refused: boolean, why: string = Refuses("useMemory takes true or false", started.useMemory, value)
			if not refused then
				return false, `AntiEsp.useMemory({value}) with memory {on} went another way: {why}`
			elseif started.memoryOn() ~= on then
				return false, `A refused AntiEsp.useMemory({value}) left memory {started.memoryOn()}, not {on}`
			end
		end

		local refused: boolean, why: string = Refuses("true or false, not nil", started.useMemory, nil)
		if not refused then
			return false, `AntiEsp.useMemory(nil) with memory {on} went another way: {why}`
		elseif started.memoryOn() ~= on then
			return false, `A refused AntiEsp.useMemory(nil) left memory {started.memoryOn()}, not {on}`
		end
	end

	return true, nil
end
