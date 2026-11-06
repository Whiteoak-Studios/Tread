--[[
    A read never crosses an epoch change: until the first sample after a
    teleport, a time answers the last sample before it, held exactly with
    nothing taken toward the later one, and from that sample's tick on the
    later epoch answers; each side still interpolates between its own
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 3
local BEFORE: vector = vector.create(0, 2, -4) -- The last place before the teleport, at tick 10
local AFTER: vector = vector.create(50, 8, 30) -- The first after it, at tick 11

type Write = { tick: number, position: vector, yaw: number, epoch: number }
type Read = { time: number, position: vector, yaw: number, epoch: number }

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()
	local writes: { Write } = {
		{ tick = 9, position = vector.create(-1, 2, -4), yaw = 0, epoch = 0 },
		{ tick = 10, position = BEFORE, yaw = 0, epoch = 0 },
		{ tick = 11, position = AFTER, yaw = math.pi / 2, epoch = 1 }, -- Teleported, which bumps the epoch
		{ tick = 12, position = vector.create(51, 8, 30), yaw = math.pi / 2, epoch = 1 },
	}

	for _, write: Write in writes do
		state.position = write.position
		state.facing = write.yaw
		state.epoch = write.epoch
		History.write(SLOT, write.tick, state, 0)
	end

	local reads: { Read } = {
		{ time = 9.5, position = vector.create(-0.5, 2, -4), yaw = 0, epoch = 0 },
		{ time = 10, position = BEFORE, yaw = 0, epoch = 0 },
		{ time = 10.25, position = BEFORE, yaw = 0, epoch = 0 }, -- Before the change's tick, the earlier side held
		{ time = 10.5, position = BEFORE, yaw = 0, epoch = 0 },
		{ time = 10.999, position = BEFORE, yaw = 0, epoch = 0 },
		{ time = 11, position = AFTER, yaw = math.pi / 2, epoch = 1 }, -- On the change's tick, the later side
		{ time = 11.5, position = vector.create(50.5, 8, 30), yaw = math.pi / 2, epoch = 1 },
	}

	for _, read: Read in reads do
		local sample = History.sampleAt(SLOT, read.time)
		if sample == nil then
			return false, `A read at {read.time}, on one side of the change, answered nil`
		elseif sample.epoch ~= read.epoch or sample.position ~= read.position then
			local got: string = `epoch {sample.epoch} at {sample.position}`
			return false, `A read at {read.time} answered {got}, not epoch {read.epoch} at {read.position}`
		elseif math.abs(sample.yaw - read.yaw) > 1e-9 then
			return false, `A read at {read.time} answered yaw {sample.yaw}, not {read.yaw}`
		end
	end

	return true, nil
end
