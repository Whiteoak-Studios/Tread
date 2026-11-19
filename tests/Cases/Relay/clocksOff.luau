--[[
    With relay.clocks off, a worker's Remote.run gives no clocks, the pool
    keeps none and the relay's rings stay empty; on, it gives the same
    result byte for byte beside one clocks buffer it keeps run to run
--]]

--!strict
local Environment = require("../../Environment")
local Layouts = require("../../Fixtures/Relay/Layouts")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local REMOTE: string = "src/Server/Relay/Remote.luau"
local SLOTS: number = 4096 -- Constants.SLOTS
local ROW_BYTES: number = SLOTS // 8
local WORKERS: number = 2
local RUNS: number = 2

-- The settings a worker's Remote.setup takes, the example's as the front works them out, clocks set per case
local function settings(clocks: boolean): { [string]: any }
	return {
		relayRate = 20,
		enter = 950,
		leave = 1000,
		sleepers = 500,
		npcs = 800,
		nearEnterSquared = 40000,
		nearLeaveSquared = 48400,
		nearAim = 20,
		nearFloor = 15,
		farAim = 15,
		farFloor = 10,
		weightNear = 1,
		weightFar = 0.5,
		weightShooter = 2,
		weightCone = 1.5,
		shotRate = 10,
		soft = 64000,
		hard = 96000,
		npcNearSquared = 38809,
		npcFarRate = 2,
		earshot = { 1600, 3600, 3600, 3600 },
		outOfView = nil,
		changes = true,
		clocks = clocks,
	}
end

-- A run's two hand-ins for one viewer with no body and no target, over a world with no bodies
local function handIns(Wire: any, world: any, run: number): (buffer, buffer)
	local shared: buffer = Wire.writeShared(world, {
		run = run,
		tick = run,
		elapsed = 1,
		wire = run,
		places = 0,
		looks = {},
		lookCount = 0,
		helds = {},
		heldCount = 0,
		observing = false,
		observed = {},
		observedCount = 0,
		kinds = buffer.create(SLOTS),
		teams = buffer.create(SLOTS * 8),
	})

	local hand: { [string]: any } = {
		id = 1,
		slot = nil,
		target = nil,
		position = vector.zero,
		look = nil,
		acknowledged = 0,
		received = 0,
		sequence = 0,
		back = false,
		traffic = 0,
		team = 0 / 0,
		row = 0,
	}
	local rows: buffer = buffer.create(ROW_BYTES)

	return shared, Wire.writeOwn(Wire.calls(), { hand }, 1, rows, rows, false)
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Wire: any = globals.require(tread.Server.Relay.Wire)
	local world: any = globals.require(tread.Server.Relay.Turn).world

	-- 1) Remote.run straight: off gives no clocks, on gives the same result and one buffer it keeps
	local off: any = Environment.load(REMOTE)
	local on: any = Environment.load(REMOTE)
	off.setup(settings(false))
	on.setup(settings(true))

	local kept: buffer? = nil
	for run: number = 1, RUNS do
		local shared: buffer, own: buffer = handIns(Wire, world, run)
		local plain: buffer, none: buffer? = off.run(shared, own)
		local timed: buffer, clocks: buffer? = on.run(shared, own)

		if none ~= nil then
			return false, `With clocks off, run {run}'s Remote.run gave clocks beside its result`
		elseif buffer.tostring(plain) ~= buffer.tostring(timed) then
			return false, `With clocks on, run {run}'s result came out other bytes than with them off`
		elseif clocks == nil or buffer.len(clocks) ~= Wire.CLOCK_BYTES then
			return false, `With clocks on, run {run}'s Remote.run gave no clocks of {Wire.CLOCK_BYTES} B`
		elseif kept ~= nil and clocks ~= kept then
			return false, `With clocks on, run {run}'s Remote.run gave a new clocks buffer, not the one it keeps`
		end

		for _, name: string in Wire.CLOCKS do
			local seconds: number = buffer.readf64(clocks, Wire.CLOCK_AT[name])
			if not (seconds >= 0) then
				return false, `With clocks on, run {run}'s {name} read {seconds} s`
			end
		end

		kept = clocks
	end

	-- 2) Through the relay with clocks off, on stand-in workers and in process: the pool keeps none, no ring fills
	local Harness: any = Layouts.harness()
	local workers: any = Harness.new(nil, nil, WORKERS)
	workers:viewer("Far")

	local Serial: any = Environment.load(HARNESS)
	local serial: any = Serial.new()
	serial:viewer("Near")

	workers:runs(RUNS)
	serial:runs(RUNS)

	for worker: number = 1, WORKERS do
		local start: number, _, clocks: buffer?, landed: number = workers.pool:times(worker)
		if start == 0 or clocks ~= nil or landed ~= 0 then
			return false, `With clocks off, worker {worker} ran no round or its pool kept clocks landed at {landed}`
		end
	end

	if next(Harness.Relay.clocks()) ~= nil or next(Serial.Relay.clocks()) ~= nil then
		return false, "With clocks off, the relay made rings for its clocks"
	end

	return true, nil
end
