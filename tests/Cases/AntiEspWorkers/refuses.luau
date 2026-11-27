--[[
    The workers' side refuses its calls before its start, a start with no
    whole count of workers from 1, no include list or no fail-open time, a
    second start and a test packed with no idle worker; useWorkers a non-boolean
--]]

--!strict
local Environment = require("../../Environment")
local StandIn = require("../../Fixtures/AntiEspWorkers/Pool")

local WORKERS: string = "src/Server/AntiEspWorkers/init.luau"
local ANTI_ESP: string = "src/Server/AntiEsp.luau"
local POOL: string = "ReplicatedStorage.Packages.Tread.Server.RelayWorkers.Pool"
local FAIL_OPEN: number = 0.15

type Refusal = { name: string, call: () -> (), says: string }

-- Why a call that must be refused was not, or nil when it was with a message that says so
local function refused(refusal: Refusal): string?
	local ran: boolean, failure: any = pcall(refusal.call)
	if ran then
		return `{refusal.name} was taken`
	elseif string.find(tostring(failure), refusal.says, 1, true) == nil then
		return `{refusal.name} was refused as "{failure}"`
	end

	return nil
end

local function land(_: number, _: number, _: boolean?, _: number, _: number) end

return function (): (boolean, string | nil)
	local override: { [string]: any } = StandIn.override()
	local AntiEspWorkers: any = Environment.load(WORKERS, { [POOL] = override })
	local origins: { vector } = { vector.zero }
	local ends: { vector } = { vector.one }

	local refusals: { Refusal } = {
		{
			name = "collect before start",
			call = function ()
				AntiEspWorkers.collect(land, 0)
			end,
			says = "before AntiEspWorkers.start",
		},
		{
			name = "send before start",
			call = function ()
				AntiEspWorkers.send(1, 0, 0)
			end,
			says = "before AntiEspWorkers.start",
		},
		{
			name = "a count of 0",
			call = function ()
				AntiEspWorkers.start(0, {}, FAIL_OPEN)
			end,
			says = "whole number of workers from 1, not 0",
		},
		{
			name = "a count of 1.5",
			call = function ()
				AntiEspWorkers.start(1.5, {}, FAIL_OPEN)
			end,
			says = "not 1.5",
		},
		{
			name = "a count of -1",
			call = function ()
				AntiEspWorkers.start(-1, {}, FAIL_OPEN)
			end,
			says = "not -1",
		},
		{
			name = "a count of NaN",
			call = function ()
				AntiEspWorkers.start(0 / 0, {}, FAIL_OPEN)
			end,
			says = "whole number of workers",
		},
		{
			name = "an endless count",
			call = function ()
				AntiEspWorkers.start(math.huge, {}, FAIL_OPEN)
			end,
			says = "whole number of workers",
		},
		{
			name = "an include list that is no table",
			call = function ()
				AntiEspWorkers.start(2, "Occluders", FAIL_OPEN)
			end,
			says = "include list as a table",
		},
		{
			name = "a fail-open time of 0",
			call = function ()
				AntiEspWorkers.start(2, {}, 0)
			end,
			says = "fail-open time in seconds above 0, not 0",
		},
		{
			name = "an endless fail-open time",
			call = function ()
				AntiEspWorkers.start(2, {}, math.huge)
			end,
			says = "fail-open time in seconds above 0",
		},
	}

	for _, refusal: Refusal in refusals do
		local problem: string? = refused(refusal)
		if problem then
			return false, problem
		end
	end

	if override.made ~= nil then
		return false, "A refused start made a pool"
	end

	AntiEspWorkers.start(2, {}, FAIL_OPEN)
	local pool: any = override.made

	if pool == nil or pool.count ~= 2 or pool.name ~= "TreadAntiEspWorkers" then
		return false, "The start made no pool of 2 workers in TreadAntiEspWorkers"
	end

	local after: { Refusal } = {
		{
			name = "a second start",
			call = function ()
				AntiEspWorkers.start(2, {}, FAIL_OPEN)
			end,
			says = "runs once",
		},
		{
			name = "a test packed before any collect",
			call = function ()
				AntiEspWorkers.add(1, 1, 1, origins, ends)
			end,
			says = "no idle worker",
		},
	}

	for _, refusal: Refusal in after do
		local problem: string? = refused(refusal)
		if problem then
			return false, problem
		end
	end

	-- Every worker unready: the collect finds none idle and none out, and a test packed then is refused
	pool.readyCount = 0
	local idle: number = AntiEspWorkers.collect(land, 0)
	if idle ~= 0 then
		return false, `The collect found {idle} idle with no worker ready`
	end

	local problem: string? = refused({
		name = "a test packed with no worker ready",
		call = function ()
			AntiEspWorkers.add(1, 1, 1, origins, ends)
		end,
		says = "no idle worker",
	})

	if problem then
		return false, problem
	end

	-- The switch takes true or false alone
	local AntiEsp: any = Environment.load(ANTI_ESP)
	problem = refused({
		name = "useWorkers with a string",
		call = function ()
			AntiEsp.useWorkers("on")
		end,
		says = "takes true or false, not on",
	})

	if problem then
		return false, problem
	end

	AntiEsp.useWorkers(true)
	if not AntiEsp.workersOn() then
		return false, "useWorkers(true) left the switch off"
	end

	AntiEsp.useWorkers(false)
	if AntiEsp.workersOn() then
		return false, "useWorkers(false) left the switch on"
	end

	return true, nil
end
