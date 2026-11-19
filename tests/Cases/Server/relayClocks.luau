--[[
    With relay.clocks on, stats gives relayClocks, every section's last and
    p95 as numbers from 0, in process and on stand-in workers, with both of
    the relay's flushes timed; with it off, on either, it gives none
--]]

--!strict
local Lockstep = require("../../Fixtures/Server/Lockstep")

local WORKERS: number = 2
local TIMEOUT: number = 60 -- Seconds, far past when any round here lands
local TICKS: number = 10

-- The sections each side reaches in some run, whose p95 over ten runs, their slowest, is above 0
local REACHED: { [string]: { string } } = {
	serial = { "head", "walk", "file", "inProcess", "flushTick" },
	workers = { "head", "turns", "run", "walk", "handIn", "flushTick", "open", "land", "sends", "flushFinish", "round" },
}

-- And those only a round on the workers reaches, which read 0 in process
local WORKERS_ONLY: { string } = { "turns", "run", "handIn", "open", "land", "sends", "flushFinish", "round" }

type Side = Lockstep.Side

-- Ten relay ticks on each side, a workers side's round delivered after each and its last brought in after
local function run(sides: { Side }, pooled: { [Side]: boolean })
	for _ = 1, TICKS do
		for _, side: Side in sides do
			Lockstep.beat(side, 1)
			if pooled[side] then
				side.pool:deliver()
			end
		end
	end

	for _, side: Side in sides do
		if pooled[side] then
			Lockstep.beat(side, 1)
		end
	end
end

-- Why a side's relayClocks is wrong, or nil: a section missing, one more, one not a number from 0, one it reaches at 0
local function wrong(side: Side, clocks: any, reached: { string }, zero: { string }?): string?
	local Relay: any = side.rig:require(side.rig.tread.Server.Relay)
	local names: { [string]: boolean } = {}

	for _, name: string in Relay.CLOCKS do
		local times: any = clocks[name]
		names[name] = true

		if type(times) ~= "table" or type(times.last) ~= "number" or type(times.p95) ~= "number" then
			return `relayClocks gave the {name} section no last and p95`
		elseif not (times.last >= 0 and times.p95 >= 0) then
			return `relayClocks gave the {name} section a last of {times.last} and a p95 of {times.p95}`
		end
	end

	for name: string in clocks do
		if not names[name] then
			return `relayClocks gave {name}, which is no section of the relay's clocks`
		end
	end

	for _, name: string in reached do
		if not (clocks[name].p95 > 0) then
			return `relayClocks gave the {name} section a p95 of 0 over ten runs`
		end
	end

	for _, name: string in zero or {} do
		if clocks[name].p95 ~= 0 or clocks[name].last ~= 0 then
			return `relayClocks gave the {name} section above 0 in process`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local relay: Lockstep.Relay = { workers = WORKERS, timeout = TIMEOUT }
	local serial: Side = Lockstep.side(nil, true)
	local workers: Side = Lockstep.side(relay, true)
	local serialOff: Side = Lockstep.side(nil)
	local workersOff: Side = Lockstep.side(relay)

	run(
		{ serial, workers, serialOff, workersOff },
		{ [serial] = false, [workers] = true, [serialOff] = false, [workersOff] = true }
	)

	for name: string, side: Side in { serial = serialOff, workers = workersOff } do
		if side.server:stats().relayClocks ~= nil then
			return false, `With clocks off, the {name} server's stats gave relayClocks`
		end
	end

	for name: string, side: Side in { serial = serial, workers = workers } do
		local clocks: any = side.server:stats().relayClocks
		if type(clocks) ~= "table" then
			return false, `With clocks on, the {name} server's stats gave no relayClocks`
		end

		local why: string? = wrong(side, clocks, REACHED[name], name == "serial" and WORKERS_ONLY or nil)
		if why then
			return false, `With clocks on, the {name} server: {why}`
		end
	end

	return true, nil
end
