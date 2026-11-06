--[[
    A woken sleeper's seeded lying sample answers for every time the
    history holds up to the woken character's first sample, with its own
    epoch and held, never interpolated toward it; a cleared slot answers
    nothing until its next life writes, and only from that write on
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOT: number = 9
local OTHER: number = 10 -- A body that keeps stepping, so the history's newest tick moves on
local WAKE: number = 50 -- The relay tick the sleeper wakes on
local SLEPT_EPOCH: number = 3
local WOKEN_EPOCH: number = 4 -- The wake bumps the epoch
local BED: vector = vector.create(20, 1, -8) -- Where the sleeper lay

type Read = { time: number, x: number?, epoch: number? }

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	History.start(Example.shared(), Example.server())

	local state = State.new()
	for tick: number = WAKE - 25, WAKE do
		History.write(OTHER, tick, state, 0)
	end

	History.seed(SLOT, WAKE, { epoch = SLEPT_EPOCH, position = BED, platform = 0, yaw = math.pi / 2 })

	-- The woken character stands up beside its bed a tick later
	state.position = vector.create(22, 1, -8)
	state.epoch = WOKEN_EPOCH
	History.write(SLOT, WAKE + 1, state, 0)
	History.write(OTHER, WAKE + 1, State.new(), 0)

	local reads: { Read } = {
		{ time = WAKE - 19, x = BED.x, epoch = SLEPT_EPOCH }, -- The history's oldest end, 20 ticks back from the newest
		{ time = WAKE - 19.5, x = nil, epoch = nil },
		{ time = WAKE - 7.5, x = BED.x, epoch = SLEPT_EPOCH },
		{ time = WAKE, x = BED.x, epoch = SLEPT_EPOCH },
		{ time = WAKE + 0.5, x = BED.x, epoch = SLEPT_EPOCH }, -- Before the wake's epoch change takes effect, held
		{ time = WAKE + 1, x = 22, epoch = WOKEN_EPOCH },
	}

	for _, read: Read in reads do
		local sample = History.sampleAt(SLOT, read.time)
		local x: number? = sample and sample.position.x
		local epoch: number? = sample and sample.epoch

		if x ~= read.x or epoch ~= read.epoch then
			return false, `At {read.time} the woken slot read x {x} in epoch {epoch}, not x {read.x} in {read.epoch}`
		end
	end

	local lying = History.sampleAt(SLOT, WAKE - 1)
	if lying.posture ~= "Downed" or math.abs(lying.yaw - math.pi / 2) > 1e-9 then
		return false, `The lying sample read {lying.posture} at yaw {lying.yaw}, not Downed at the bed's yaw`
	end

	History.clear(SLOT)

	if History.sampleAt(SLOT, WAKE + 1) ~= nil or History.sampleAt(SLOT, WAKE) ~= nil then
		return false, "A cleared slot still answered a read"
	end

	-- Its next life starts fresh, and none of the last one's samples come back
	state.position = vector.create(-30, 2, 4)
	state.epoch = 0
	History.write(SLOT, WAKE + 2, state, 0)
	History.write(OTHER, WAKE + 2, State.new(), 0)

	local fresh = History.sampleAt(SLOT, WAKE + 2)
	if fresh == nil or fresh.position ~= state.position then
		return false, `The next life's first sample read {fresh and fresh.position}, not {state.position}`
	elseif History.sampleAt(SLOT, WAKE + 1.5) ~= nil then
		return false, "The next life answered a time before its first sample"
	end

	return true, nil
end
