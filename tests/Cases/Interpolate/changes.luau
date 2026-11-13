--[[
    A change record is rebuilt against the record its base names and drawn
    as that record sent whole is: a block of whole records goes on as it
    did, and a chain of changes, each against the newest acknowledged
    record, poses its slot frame for frame as the same records sent whole
--]]

--!strict
local Changes = require("../../Fixtures/Interpolate/Changes")
local Viewer = require("../../Fixtures/Interpolate/Viewer")

local MOVER: number = 5 -- Sent as changes once revealed
local STILL: number = 6 -- Sent whole in every block beside it
local GENERATION: number = 1
local FIRST: number = 10
local FRAME: number = 0.05 -- Seconds a frame, one relay tick at 20 Hz
local AFTER: number = 10 -- Frames drawn past the last block, so the render time passes every record
local WHOLE_BYTES: number = 16
local START: vector = vector.create(100, 10, -200)
local PITCH_STEP: number = (math.pi / 2) / 127 -- Radians a record's i8 pitch steps by

-- Every field of a state a pose fills
local POSED: { string } =
	{ "position", "facing", "lean", "velocity", "mode", "posture", "platform", "grounded", "sprint", "aim", "epoch" }

-- Why two drawn states differ, or nil when every field a pose fills is the same
local function differs(a: { [string]: any }, b: { [string]: any }): string?
	for _, name: string in POSED do
		if a[name] ~= b[name] then
			return `its {name} was {a[name]}, not {b[name]}`
		end
	end

	return nil
end

return function (): (boolean, string | nil)
	local changed = Viewer.new()
	local whole = Viewer.new()

	for _, viewer in { changed, whole } do
		viewer.announce(MOVER, GENERATION, "A")
		viewer.announce(STILL, GENERATION, "A")
	end

	local crouched: number = changed.word({ posture = "Crouch", sprint = true })

	local function record(slot: number, fields: { [string]: any }): buffer
		local all: { [string]: any } = { slot = slot, generation = GENERATION, position = START }
		for name: string, value: any in fields do
			all[name] = value
		end

		return Changes.record(all)
	end

	-- Whether both viewers draw both slots alike at the render time, and why not
	local function alike(when: string): string?
		for _, slot: number in { MOVER, STILL } do
			local drawn: boolean, state: any, pitch: number = changed.pose(slot)
			local wholeDrawn: boolean, wholeState: any, wholePitch: number = whole.pose(slot)
			local why: string? = differs(state, wholeState)

			if drawn ~= wholeDrawn or pitch ~= wholePitch then
				return `{when}, slot {slot} drew {drawn} at pitch {pitch}, sent whole {wholeDrawn} at {wholePitch}`
			elseif drawn and why then
				return `{when}, slot {slot} was drawn otherwise than sent whole: {why}`
			end
		end

		return nil
	end

	local function frames(count: number, when: string): string?
		for _ = 1, count do
			changed.Interpolate.frame(FRAME)
			whole.Interpolate.frame(FRAME)

			local why: string? = alike(when)
			if why then
				return why
			end
		end

		return nil
	end

	-- 1) A block of whole records, both viewers alike, acknowledged as before
	local still: buffer = record(STILL, { position = START + vector.create(-6, 0, 0) })
	local previous: buffer = record(MOVER, {})
	local opening: buffer = Changes.block({
		sequence = 1,
		tick = FIRST,
		reveals = {
			{ slot = MOVER, generation = GENERATION, kind = "Player" },
			{ slot = STILL, generation = GENERATION, kind = "Player" },
		},
		records = { previous, still },
	})

	changed.Interpolate.receive(opening)
	whole.Interpolate.receive(opening)

	local acknowledged: number, mask: number = changed.Interpolate.received()
	if acknowledged ~= 1 or mask ~= 0 then
		return false, `A block of whole records left the acknowledgment at {acknowledged} with {mask}, not 1 with 0`
	end

	-- 2) A walk 3 relay ticks on, then Y past an i8 step with a turn and a look up, then a crouched sprint, each against
	-- the one before it, the newest the server knows this client acknowledged
	local steps: { { tick: number, fields: { [string]: any } } } = {
		{ tick = FIRST + 3, fields = { position = START + vector.create(1.5, 0, -0.75) } },
		{
			tick = FIRST + 5,
			fields = { position = START + vector.create(2.5, 10, -1), yaw = 1, pitch = 10 * PITCH_STEP },
		},
		{
			tick = FIRST + 6,
			fields = {
				position = START + vector.create(3, 10.5, -1.25),
				yaw = 1.25,
				pitch = 10 * PITCH_STEP,
				word = crouched,
			},
		},
	}

	local previousTick: number = FIRST
	for index: number, step in steps do
		local why: string? = frames(step.tick - previousTick, `Before tick {step.tick}`)
		if why then
			return false, why
		end

		local current: buffer = record(MOVER, step.fields)
		local change: buffer = Changes.change(current, previous, step.tick - previousTick)
		if buffer.len(change) >= WHOLE_BYTES then
			return false, `The change at tick {step.tick} took {buffer.len(change)} B, no fewer than a whole record`
		end

		changed.Interpolate.receive(
			Changes.block({ sequence = index + 1, tick = step.tick, records = { still }, changes = { change } })
		)
		whole.Interpolate.receive(
			Changes.block({ sequence = index + 1, tick = step.tick, records = { still, current } })
		)

		local newest: number, bits: number = changed.Interpolate.received()
		local wholeNewest: number, wholeBits: number = whole.Interpolate.received()
		if newest ~= wholeNewest or bits ~= wholeBits then
			return false, `The block at tick {step.tick} was acknowledged as {newest} with {bits}, whole {wholeNewest}`
		end

		previous = current
		previousTick = step.tick
	end

	-- 3) Past the newest, both carry on and hold alike
	local why: string? = frames(AFTER, "Past the last block")
	if why then
		return false, why
	end

	if #changed.reveals ~= 2 or #changed.hides ~= 0 then
		return false, `The changes told {#changed.reveals} reveals and {#changed.hides} hides, not the 2 reveals alone`
	end

	return true, nil
end
