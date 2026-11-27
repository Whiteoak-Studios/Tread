--[[
    The history refuses every call before its start and a second start, a
    slot outside the table, a tick that isn't a whole number or isn't newer
    than the slot's last, a rider with no platform place, a platform or
    epoch its bits can't hold, a render time that isn't finite, and rewind
    terms below 0
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local STATE: string = "src/Step/State.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SLOTS: number = 4096

type Refusal = { name: string, call: () -> (), says: string }

-- Why a refusal did not happen as it should, or nil when the call errored saying what it was due to say
local function refused(refusal: Refusal): string?
	local passed: boolean, failure: any = pcall(refusal.call)
	if passed then
		return `{refusal.name} was taken`
	elseif not string.find(tostring(failure), refusal.says, 1, true) then
		return `{refusal.name} was refused as "{failure}", which doesn't say "{refusal.says}"`
	end

	return nil
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local State: any = Environment.load(STATE)
	local Example: any = Environment.load(EXAMPLE)
	local state = State.new()
	local lying = { epoch = 0, position = vector.zero, platform = 0, yaw = 0 }

	local before: { Refusal } = {
		{
			name = "A write before start",
			call = function ()
				History.write(0, 1, state, 0)
			end,
			says = "before History.start",
		},
		{
			name = "A read before start",
			call = function ()
				History.sampleAt(0, 1)
			end,
			says = "before History.start",
		},
		{
			name = "A seed before start",
			call = function ()
				History.seed(0, 1, lying)
			end,
			says = "before History.start",
		},
		{
			name = "A rewind before start",
			call = function ()
				History.rewindFor(1, 0, 0, 0, 0, 1)
			end,
			says = "before History.start",
		},
	}

	for _, refusal: Refusal in before do
		local failure: string? = refused(refusal)
		if failure then
			return false, failure
		end
	end

	History.start(Example.shared(), Example.server())

	for tick: number = 1, 10 do
		state.position = vector.create(tick, 0, 0)
		History.write(0, tick, state, 0)
	end

	local rider = State.new()
	rider.platform = 3

	local wide = State.new()
	wide.platform = 128

	local late = State.new()
	late.epoch = 256

	local after: { Refusal } = {
		{
			name = "A second start",
			call = function ()
				History.start(Example.shared(), Example.server())
			end,
			says = "runs once",
		},
		{
			name = "A write to slot -1",
			call = function ()
				History.write(-1, 11, state, 0)
			end,
			says = "slot from 0",
		},
		{
			name = `A write to slot {SLOTS}`,
			call = function ()
				History.write(SLOTS, 11, state, 0)
			end,
			says = "slot from 0",
		},
		{
			name = "A write to slot 1.5",
			call = function ()
				History.write(1.5, 11, state, 0)
			end,
			says = "slot from 0",
		},
		{
			name = "A write at tick -1",
			call = function ()
				History.write(1, -1, state, 0)
			end,
			says = "whole number",
		},
		{
			name = "A write at tick 11.5",
			call = function ()
				History.write(1, 11.5, state, 0)
			end,
			says = "whole number",
		},
		{
			name = "A write at a NaN tick",
			call = function ()
				History.write(1, 0 / 0, state, 0)
			end,
			says = "whole number",
		},
		{
			name = "A write at the slot's own tick",
			call = function ()
				History.write(0, 10, state, 0)
			end,
			says = "already holds",
		},
		{
			name = "A write older than the slot's",
			call = function ()
				History.write(0, 9, state, 0)
			end,
			says = "already holds",
		},
		{
			name = "A rider with no platform place",
			call = function ()
				History.write(2, 11, rider, 0)
			end,
			says = "platform's position",
		},
		{
			name = "A write on platform 128",
			call = function ()
				History.write(2, 11, wide, 0)
			end,
			says = "platform is 0 to 127",
		},
		{
			name = "A write in epoch 256",
			call = function ()
				History.write(2, 11, late, 0)
			end,
			says = "epoch is a u8",
		},
		{
			name = "A write in epoch 256 after a gap",
			call = function ()
				History.write(0, 30, late, 0)
			end,
			says = "epoch is a u8",
		},
		{
			name = "A read of slot 4096",
			call = function ()
				History.sampleAt(SLOTS, 10)
			end,
			says = "slot from 0",
		},
		{
			name = "A read at NaN",
			call = function ()
				History.sampleAt(0, 0 / 0)
			end,
			says = "finite number",
		},
		{
			name = "A read at infinity",
			call = function ()
				History.sampleAt(0, math.huge)
			end,
			says = "finite number",
		},
		{
			name = "A seed of slot -2",
			call = function ()
				History.seed(-2, 10, lying)
			end,
			says = "slot from 0",
		},
		{
			name = "A seed at tick 0.5",
			call = function ()
				History.seed(3, 0.5, lying)
			end,
			says = "whole number",
		},
		{
			name = "A clear of slot 4096",
			call = function ()
				History.clear(SLOTS)
			end,
			says = "slot from 0",
		},
		{
			name = "A rewind at tick -1",
			call = function ()
				History.rewindFor(-1, 0, 0, 0, 0, 1)
			end,
			says = "whole number",
		},
		{
			name = "A rewind of a NaN claim",
			call = function ()
				History.rewindFor(11, 0, 0, 0, 0, 0 / 0)
			end,
			says = "finite number",
		},
		{
			name = "A rewind with a negative RTT",
			call = function ()
				History.rewindFor(11, -0.1, 0, 0, 0, 1)
			end,
			says = "of 0 or more",
		},
		{
			name = "A rewind with NaN jitter",
			call = function ()
				History.rewindFor(11, 0, 0 / 0, 0, 0, 1)
			end,
			says = "of 0 or more",
		},
		{
			name = "A rewind with a negative wait",
			call = function ()
				History.rewindFor(11, 0, 0, -1, 0, 1)
			end,
			says = "of 0 or more",
		},
		{
			name = "A rewind with an infinite delay",
			call = function ()
				History.rewindFor(11, 0, 0, 0, math.huge, 1)
			end,
			says = "of 0 or more",
		},
	}

	for _, refusal: Refusal in after do
		local failure: string? = refused(refusal)
		if failure then
			return false, failure
		end
	end

	-- A refused write leaves the slot as it was, its held ticks unwritten, and the refused slots hold nothing
	for tick: number = 1, 10 do
		local kept = History.sampleAt(0, tick + 0.5)
		local want: number = math.min(tick + 0.5, 10)

		if kept == nil or kept.position.x ~= want then
			return false, `After the refused writes slot 0 read {kept and kept.position} at {tick + 0.5}, not x {want}`
		end
	end

	if History.sampleAt(2, 11) ~= nil then
		return false, "A refused write to an empty slot left it answering a read"
	end

	return true, nil
end
