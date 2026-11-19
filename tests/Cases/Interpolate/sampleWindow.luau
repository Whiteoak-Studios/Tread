--[[
    Interpolate.sample draws one set of samples alike from a live ring that
    has wrapped and from a contiguous run of a longer list: between two, at
    a move from rest, past the newest and held there, and before the oldest
--]]

--!strict
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local RING: number = 8 -- The samples a live ring keeps
local HEAD: number = 2 -- Where the wrapped ring's newest sits
local LONGER: number = 12 -- The contiguous list the window is the last 8 of
local FIRST: number = 100 -- The oldest sample's relay tick
local TICK_BYTES: number = 8
local CLOSE: number = 1e-9

-- Each sample's place along X, resting from the fourth to the fifth so the move after it starts from rest
local PLACES: { number } = { 0, 1, 2, 3, 3, 4, 5, 6 }

-- Render times: between two, inside the rest, as the move from rest starts, past the newest, held past that, before
local TIMES: { number } = { 100.5, 103.25, 104.5, 107.5, 109.5, 99 }

return function (): (boolean, string | nil)
	local viewer: any = Viewer.new()
	local Interpolate: any = viewer.Interpolate
	local Record: any = viewer.Record
	local State: any = viewer.State
	local bytes: number = viewer.Constants.RECORD_BYTES

	-- One sample's record, its slot 0 and its place along X
	local function write(records: buffer, index: number, sample: number)
		local record: any = Record.new()
		record.position = vector.create(PLACES[sample], 0, 0)
		record.yaw = sample * 0.1
		record.pitch = sample * 0.05
		Record.write(record, records, index * bytes, viewer.limits)
	end

	-- The ring as a live slot's wraps: the sample back b from the newest at (HEAD - b) % 8
	local ringTicks: buffer = buffer.create(RING * TICK_BYTES)
	local ringRecords: buffer = buffer.create(RING * bytes)
	for back: number = 0, RING - 1 do
		local sample: number = RING - back
		local index: number = (HEAD - back) % RING
		buffer.writef64(ringTicks, index * TICK_BYTES, FIRST + sample - 1)
		write(ringRecords, index, sample)
	end

	-- The same eight as the last of a longer list, oldest first, the window over them starting at its fifth
	local base: number = LONGER - RING
	local runTicks: buffer = buffer.create(LONGER * TICK_BYTES)
	local runRecords: buffer = buffer.create(LONGER * bytes)
	for sample: number = 1, RING do
		buffer.writef64(runTicks, (base + sample - 1) * TICK_BYTES, FIRST + sample - 1)
		write(runRecords, base + sample - 1, sample)
	end

	for _, at: number in TIMES do
		local wrapped: any = State.new()
		local run: any = State.new()
		local ringShown: boolean, ringPitch: number =
			Interpolate.sample(ringTicks, ringRecords, 0, HEAD, RING, at, wrapped)
		local runShown: boolean, runPitch: number =
			Interpolate.sample(runTicks, runRecords, base, RING - 1, RING, at, run)

		if ringShown ~= runShown then
			return false, `At {at} the wrapped ring drew {ringShown} and the window {runShown}`
		elseif ringShown then
			if vector.magnitude(wrapped.position - run.position) > CLOSE then
				return false, `At {at} the wrapped ring drew {wrapped.position} and the window {run.position}`
			elseif vector.magnitude(wrapped.velocity - run.velocity) > CLOSE then
				return false, `At {at} the wrapped ring moved at {wrapped.velocity} and the window {run.velocity}`
			elseif math.abs(wrapped.facing - run.facing) > CLOSE or math.abs(ringPitch - runPitch) > CLOSE then
				return false,
					`At {at} the two faced {wrapped.facing} and {run.facing}, pitched {ringPitch} and {runPitch}`
			end
		end
	end

	-- The window drew what the samples give, so neither agreed by drawing nothing: halfway between the first two
	local between: any = State.new()
	local shown: boolean = Interpolate.sample(runTicks, runRecords, base, RING - 1, RING, TIMES[1], between)
	if not shown or math.abs(between.position.x - 0.5) > CLOSE then
		return false, `Between the first two samples the window drew {between.position}, not halfway`
	end

	return true, nil
end
