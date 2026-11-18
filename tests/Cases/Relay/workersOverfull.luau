--[[
    A target handed more watchers than it takes while a round is out: an
    in-process one raised at the finish and at a drop, and a worker's at the
    finish, each naming the target the serial relay names
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local WORKERS: number = 2
local EXTRA_WATCHERS: number = 32 -- One more than a target takes
local CENTER: vector = vector.create(600, 0, 2600)
local OVERFULL: string = "(%S+ has more than the %d+ watchers one target takes)"

type Side = {
	Harness: any,
	harness: any,
	clients: { [string]: any },
	extras: { any },
}

-- The overfull error's text without where it was raised from, or what else a run gave
local function named(ran: boolean, failure: any): string
	if ran then
		return "nothing"
	end

	return string.match(`{failure}`, OVERFULL) or `{failure}`
end

return function (): (boolean, string | nil)
	local serial: Side = { Harness = Environment.load(HARNESS), harness = nil, clients = {}, extras = {} }
	serial.harness = serial.Harness.new()

	local MixedHarness: any = Layouts.harness()
	local mixed: Side =
		{ Harness = MixedHarness, harness = MixedHarness.new(nil, nil, WORKERS), clients = {}, extras = {} }
	local sides: { Side } = { serial, mixed }

	local function join(name: string, at: vector, owned: boolean)
		for _, built: Side in sides do
			local client: any = built.harness:viewer(name)
			built.clients[name] = client
			client.viewer.position = at
			if owned then
				client.viewer.slot = built.harness:spawn("Player", at)
			end
		end
	end

	-- More watchers than the target takes join it, each homed by whether the workers are on
	local function crowd(target: string)
		for index: number = 1, EXTRA_WATCHERS do
			for _, built: Side in sides do
				local extra: any = built.harness:viewer(`{target}Watcher{index}`)
				built.harness:watch(extra, built.clients[target])
				table.insert(built.extras, extra.viewer)
			end
		end
	end

	local function clear()
		for _, built: Side in sides do
			for _, viewer: any in built.extras do
				table.remove(built.harness.viewers, table.find(built.harness.viewers, viewer))
				built.Harness.Relay.remove(viewer.key)
			end

			table.clear(built.extras)
		end
	end

	-- Both relays' runs, the mixed one's round brought in or dropped, and the error each raised
	local function both(drop: boolean): (string, string)
		local serialRan: boolean, serialFailure: any = pcall(serial.harness.run, serial.harness)

		local realPool: any = mixed.harness.pool
		if drop then
			mixed.harness.pool = {
				deliver = function (_: any)
					mixed.Harness.Relay.drop()
				end,
			}
		end

		local mixedRan: boolean, mixedFailure: any = pcall(mixed.harness.run, mixed.harness)
		mixed.harness.pool = realPool

		return named(serialRan, serialFailure), named(mixedRan, mixedFailure)
	end

	-- An in-process target, then a worker's view, so every run from here sends a round
	mixed.Harness.Relay.useWorkers(false)
	join("Near", CENTER, true)
	both(false)

	mixed.Harness.Relay.useWorkers(true)
	join("Far", CENTER + vector.create(10, 0, 0), true)
	both(false)

	mixed.Harness.Relay.useWorkers(false)
	crowd("Near")

	local checks: { { what: string, drop: boolean } } = {
		{ what = "the in-process target at the finish", drop = false },
		{ what = "the in-process target at a drop", drop = true },
	}

	for _, check in checks do
		local serialFailure: string, mixedFailure: string = both(check.drop)
		if serialFailure ~= mixedFailure or not string.find(serialFailure, "Near has more", 1, true) then
			return false, `For {check.what}, serial raised "{serialFailure}" and the workers "{mixedFailure}"`
		end
	end

	clear()
	local serialFailure: string, mixedFailure: string = both(false)
	if serialFailure ~= "nothing" or mixedFailure ~= "nothing" then
		return false, `Once the watchers left, serial raised "{serialFailure}" and the workers "{mixedFailure}"`
	end

	mixed.Harness.Relay.useWorkers(true)
	crowd("Far")
	serialFailure, mixedFailure = both(false)
	if serialFailure ~= mixedFailure or not string.find(serialFailure, "Far has more", 1, true) then
		return false, `For the worker's target, serial raised "{serialFailure}" and the workers "{mixedFailure}"`
	end

	return true, nil
end
