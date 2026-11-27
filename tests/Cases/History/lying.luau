--[[
    History.lying places the Downed shapes at a place and yaw exactly as a
    seeded lying sample reads back there, in the slot's own Sample, reading
    and writing no history, and refuses what it cannot place
--]]

--!strict
local Environment = require("../../Environment")

local HISTORY: string = "src/Server/History.luau"
local EXAMPLE: string = "tests/Fixtures/Config/Example.luau"
local SEEDED: number = 1 -- The slot a woken sleeper's lying sample is seeded in
local PLACED: number = 2 -- The slot History.lying places the same lying body in
local WAKE: number = 40
local EPOCH: number = 2
local BED: vector = vector.create(64.5, 3.125, -20.25) -- On the record's 1/64 and 1/32 grid, so it reads back as written
local YAW_STEPS: number = 12000 -- The yaw in the u16's steps of the turn, so it reads back as written
local TURN: number = 2 * math.pi
local NEAR: number = 1e-5 -- A vector holds float32, so a placed point sits within its rounding of the other's

type Capsule = { from: vector, to: vector, radius: number }

-- Why two sets of placed shapes sit apart, or nil when every capsule matches
local function apart(name: string, got: any, want: any): string?
	local capsules: { { name: string, got: Capsule, want: Capsule } } =
		{ { name = "body", got = got.body, want = want.body } }

	for zone: string, shape: Capsule in want.zones do
		table.insert(capsules, { name = zone, got = got.zones[zone], want = shape })
	end

	for _, pair in capsules do
		if
			pair.got == nil
			or vector.magnitude(pair.got.from - pair.want.from) > NEAR
			or vector.magnitude(pair.got.to - pair.want.to) > NEAR
			or pair.got.radius ~= pair.want.radius
		then
			return `{name}: the {pair.name} capsule sat apart from the seeded lying sample's`
		end
	end

	return nil
end

-- A copy of a Sample's shapes, since the slot's next read rewrites the table
local function copy(sample: any): any
	local zones: { [string]: Capsule } = {}

	for zone: string, shape: Capsule in sample.zones do
		zones[zone] = { from = shape.from, to = shape.to, radius = shape.radius }
	end

	return { body = { from = sample.body.from, to = sample.body.to, radius = sample.body.radius }, zones = zones }
end

return function (): (boolean, string | nil)
	local History: any = Environment.load(HISTORY)
	local Example: any = Environment.load(EXAMPLE)

	local early: boolean, earlyReason: any = pcall(History.lying, PLACED, BED, 0, EPOCH)
	if early or not string.find(`{earlyReason}`, "ran before History.start", 1, true) then
		return false, `History.lying ran before History.start: {earlyReason}`
	end

	History.start(Example.shared(), Example.server())

	local yaw: number = YAW_STEPS * TURN / 65536
	History.seed(SEEDED, WAKE, { epoch = EPOCH, position = BED, platform = 0, yaw = yaw })

	local seeded: any = History.sampleAt(SEEDED, WAKE)
	local seededPosition: vector, seededYaw: number = seeded.position, seeded.yaw
	local want: any = copy(seeded)

	-- 1) The same lying body placed by History.lying matches the seeded sample capsule for capsule
	local placed: any = History.lying(PLACED, BED, yaw, EPOCH)
	local failure: string? = apart("History.lying", placed, want)

	if failure then
		return false, failure
	elseif placed.posture ~= "Downed" or placed.epoch ~= EPOCH or placed.platform ~= 0 then
		return false, `History.lying placed {placed.posture} in epoch {placed.epoch} on platform {placed.platform}`
	elseif placed.position ~= seededPosition or math.abs(placed.yaw - seededYaw) > NEAR then
		return false, `History.lying lay at {placed.position} yaw {placed.yaw}, not the seeded {seededPosition}`
	end

	-- 2) A yaw a turn off places alike, read back inside the one turn
	local around: any = History.lying(PLACED, BED, yaw - TURN, EPOCH)
	failure = apart("A yaw a turn back", around, want)

	if failure then
		return false, failure
	elseif math.abs(around.yaw - seededYaw) > NEAR then
		return false, `A yaw a turn back read {around.yaw}, not {seededYaw}`
	elseif around ~= placed then
		return false, "History.lying handed out a new table, not the slot's own Sample"
	end

	-- 3) Placing the seeded slot elsewhere changes nothing its history holds
	History.lying(SEEDED, vector.create(-100, 0, 100), 1, 0)

	local again: any = History.sampleAt(SEEDED, WAKE)
	if again.position ~= seededPosition or again.epoch ~= EPOCH or apart("The history", again, want) then
		return false, `History.lying changed the seeded slot's history, which read {again.position} after it`
	end

	-- 4) The refusals
	local refusals: { { name: string, slot: number, position: vector, yaw: number, epoch: number, says: string } } = {
		{ name = "a slot past the table", slot = 4096, position = BED, yaw = 0, epoch = 0, says = "takes a slot" },
		{
			name = "a position not finite",
			slot = PLACED,
			position = vector.create(0, 0 / 0, 0),
			yaw = 0,
			epoch = 0,
			says = "finite position",
		},
		{ name = "a yaw not finite", slot = PLACED, position = BED, yaw = math.huge, epoch = 0, says = "finite yaw" },
		{ name = "an epoch past a u8", slot = PLACED, position = BED, yaw = 0, epoch = 256, says = "epoch is a u8" },
	}

	for _, refusal in refusals do
		local ran: boolean, reason: any =
			pcall(History.lying, refusal.slot, refusal.position, refusal.yaw, refusal.epoch)

		if ran or not string.find(`{reason}`, refusal.says, 1, true) then
			return false, `History.lying took {refusal.name}: {reason}`
		end
	end

	return true, nil
end
