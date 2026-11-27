--[[
    Probe P10's sampler: through a bot load's window, the box each walking
    bot's settle hands the step's exact overlap check, rebuilt from its step
    state every Heartbeat and kept in Queries' box layout
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Packages = ReplicatedStorage.Packages

local Characters = require(Packages.Tread.Server.Characters)
local Hulls = require(Packages.Tread.Step.Hulls)
local Sequence = require(Packages.Tread.Codec.Sequence)
local State = require(Packages.Tread.Step.State)

local Queries = require(ServerScriptService.Server.Parallel.Queries)
local Run = require(ServerScriptService.Server.Bots.Run)

local VALUE_BYTES: number = Queries.VALUE_BYTES
local BOX_BYTES: number = Queries.BOX_WIDTH * VALUE_BYTES
local AXES: number = 3 -- A vector's values
local HALF: number = 0.5 -- The hull's center sits half its height above the feet
local NONE: string = "none" -- The line's first failure when no read threw

type Settings = State.Settings
type StepState = State.State

-- What a bot's last read left, which its next read is compared with
type Seen = { tick: number, position: vector }

-- One load's sampling: the counts its recording gives, the boxes kept so far and each bot's last read
export type Sampler = {
	name: string,
	cap: number, -- The most boxes it keeps
	settings: Settings, -- The step block the boxes are sized by
	boxes: buffer, -- Room for the cap's boxes, the first recorded of them written
	recorded: number,
	dropped: number,
	reads: number,
	walkers: number,
	skipped: number,
	failed: number,
	failure: string?, -- The first failed read's error
	seen: { [unknown]: Seen }, -- Each bot's last read, by the key its reads name it with
}

-- What the bounds probe reads of one load
export type Recording = {
	name: string, -- The load's name
	boxes: buffer, -- Queries.BOX_WIDTH f64s a box, the center then the size, recorded boxes only
	recorded: number, -- Boxes in the buffer
	dropped: number, -- Walking boxes past the cap, not kept
	reads: number, -- Bot reads that found a new tick
	walkers: number, -- Of those, walking with a changed position, so recorded plus dropped
	skipped: number, -- Ticks lost where a bot's tick moved on by more than one between reads
	failed: number, -- Bot reads that threw
}

local Settles = {}

--[[
    A load's sampler, keeping at most cap boxes sized by the step block
    given, which a live load takes from the dev shared table
--]]

function Settles.new(name: string, cap: number, settings: Settings): Sampler
	if cap ~= cap // 1 or cap < 0 then
		error(`A sampler keeps a whole number of boxes from 0, and was given a cap of {cap}`)
	end

	return {
		name = name,
		cap = cap,
		settings = settings,
		boxes = buffer.create(cap * BOX_BYTES),
		recorded = 0,
		dropped = 0,
		reads = 0,
		walkers = 0,
		skipped = 0,
		failed = 0,
		failure = nil,
		seen = {},
	}
end

-- Writes a vector's values as f64s from a byte offset, giving the offset after them
local function put(boxes: buffer, at: number, value: vector): number
	buffer.writef64(boxes, at, value.x)
	buffer.writef64(boxes, at + VALUE_BYTES, value.y)
	buffer.writef64(boxes, at + 2 * VALUE_BYTES, value.z)

	return at + AXES * VALUE_BYTES
end

--[[
    One bot's step state at one beat. Its first read only seeds it, and a
    read of the tick it last read is passed over. A read of a new tick
    counts the ticks lost between, then for a walker whose feet moved keeps
    the box settle checked, the hull's width by its height centered half
    that height above the feet, or drops it past the cap
--]]

function Settles.read(sampler: Sampler, key: unknown, state: StepState)
	local tick: number = state.tick
	local position: vector = state.position
	local seen: Seen? = sampler.seen[key]

	if not seen then
		sampler.seen[key] = { tick = tick, position = position }
		return
	elseif tick == seen.tick then
		return
	end

	sampler.reads += 1

	local ahead: number = Sequence.difference(tick, seen.tick)
	if ahead > 1 then
		sampler.skipped += ahead - 1
	end

	if state.moveMode == "Walk" and position ~= seen.position then
		sampler.walkers += 1

		if sampler.recorded < sampler.cap then
			local settings: Settings = sampler.settings
			local height: number = Hulls.height(state, settings)
			local width: number = settings.radius + settings.radius
			local center: vector = vector.create(position.x, position.y + height * HALF, position.z)
			local at: number = put(sampler.boxes, sampler.recorded * BOX_BYTES, center)

			put(sampler.boxes, at, vector.create(width, height, width))
			sampler.recorded += 1
		else
			sampler.dropped += 1
		end
	end

	seen.tick = tick
	seen.position = position
end

-- One fleet entry's read, its character's step state reached as the fleet reaches it
local function readEntry(sampler: Sampler, entry: any)
	Settles.read(sampler, entry, Characters.stateOf(entry.character))
end

-- The sampler's counts in one line, the first failed read's error last
local function describe(sampler: Sampler): string
	local kept: string = `{sampler.recorded} kept, {sampler.dropped} dropped past the cap of {sampler.cap}`
	local walked: string = `{sampler.walkers} of them walkers that moved ({kept})`
	local lost: string = `{sampler.skipped} ticks skipped, {sampler.failed} reads threw`
	local failure: string = sampler.failure or NONE

	return `{sampler.name}: {sampler.reads} reads of a new tick, {walked}, {lost}, first failure {failure}`
end

--[[
    The probe beside a load's window, which owns its Heartbeat connection.
    Its start forgets every bot's last read and connects, last, one
    Heartbeat that reads each entry the fleet's list holds at that beat, a
    read that throws counted and its bot passed over for the beat. Its stop,
    which the run calls on every path out of the window, disconnects it and
    gives the counts' line. Counts and boxes run on across the windows it is
    started for
--]]

function Settles.probe(sampler: Sampler): Run.Probe
	local beats: RBXScriptConnection? = nil

	local function disconnect()
		local connection: RBXScriptConnection? = beats
		beats = nil

		if connection then
			connection:Disconnect()
		end
	end

	return {
		start = function (entries: { any })
			disconnect()
			table.clear(sampler.seen)

			beats = RunService.Heartbeat:Connect(function ()
				for _, entry: any in entries do
					local read: boolean, failure: any = pcall(readEntry, sampler, entry)
					if not read then
						sampler.failed += 1
						sampler.failure = sampler.failure or tostring(failure)
					end
				end
			end)
		end,

		stop = function (_: { [string]: { number } }): string
			disconnect()

			return describe(sampler)
		end,
	}
end

-- The load's recording for the bounds probe, its buffer a copy holding the recorded boxes alone
function Settles.recording(sampler: Sampler): Recording
	local size: number = sampler.recorded * BOX_BYTES
	local boxes: buffer = buffer.create(size)
	buffer.copy(boxes, 0, sampler.boxes, 0, size)

	return {
		name = sampler.name,
		boxes = boxes,
		recorded = sampler.recorded,
		dropped = sampler.dropped,
		reads = sampler.reads,
		walkers = sampler.walkers,
		skipped = sampler.skipped,
		failed = sampler.failed,
	}
end

return Settles
