--[[
    While shoot names a slot, every command the dev client sends carries
    the last shot's aim as its base look with the head level, and once
    shoot(0) stops it the look follows the camera's again
--]]

--!strict
local Mount = require("../../Fixtures/DevShots/Mount")

local OWN: number = 9
local TARGET: number = 21
local GENERATION: number = 1
local FEET: vector = vector.create(0, 50, 0)
local FAR: number = -600 -- Studs along Z the target stands, straight ahead at a yaw of 0
local AKM: number = 1
local START: number = 200 -- The relay tick the target's records start on
local BEFORE: number = 6 -- Frames drawn before firing starts
local FIRING: number = 24 -- Frames fired for
local AFTER: number = 6 -- Frames after firing stops
local CAMERA_YAW: number = 2 -- The camera's base look, radians, about 115 degrees off the target
local CAMERA_PITCH: number = 0.3
local HEAD_YAW: number = 10 -- The camera's head offset, degrees, inside the example's cone
local HEAD_PITCH: number = -5
local TURN: number = 2 * math.pi

-- One command as Tread sends it, read back off the wire straight after the frame that sampled it
type Sent = {
	shot: { [string]: number }?,
	yaw: number,
	pitch: number,
	headYaw: number,
	headPitch: number,
}

-- The dev game's input as it samples: the camera's look and head offset, and the shot list made once
local function input(command: { [string]: any })
	command.yaw = CAMERA_YAW
	command.pitch = CAMERA_PITCH
	command.headYaw = HEAD_YAW
	command.headPitch = HEAD_PITCH
	command.fields.slot = 0

	if command.fields.shots == nil then
		command.fields.shots = {}
	end
end

return function (): (boolean, string | nil)
	local mounted: Mount.Mounted = Mount.new({ input = input })
	local rig: any = mounted.rig
	local angleSteps: number = rig.Constants.ANGLE_STEPS
	local headStep: number = rig.shared.step.headCone / rig.Constants.HEAD_STEPS -- Degrees a wire step holds

	-- An angle in radians as the wire's steps of a turn, which a command's look and a shot's both count in
	local function steps(angle: number): number
		return math.round(angle / TURN * angleSteps)
	end

	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.slots({ { slot = TARGET, generation = GENERATION, rig = "A" } })
	rig.owner(rig.body(FEET, 0, START))

	local frame: number = 0
	local sent: { Sent } = {}

	-- One frame: the target's record, each command sampled read back, then the server acknowledging the newest
	local function step(count: number)
		for _ = 1, count do
			local tick: number = START + frame
			local reveals: { any }? = frame == 0 and { { slot = TARGET, generation = GENERATION, kind = "Player" } }
				or nil
			rig.relay({
				tick = tick,
				reveals = reveals,
				records = {
					{ slot = TARGET, generation = GENERATION, position = vector.create(0, FEET.y, FAR), yaw = 0 },
				},
			})

			local first: number = #mounted.sampled + 1
			rig.frames(1)

			for index: number = first, #mounted.sampled do
				local sampled: Mount.Sampled = mounted.sampled[index]
				local command: { [string]: any } = sampled.command
				table.insert(sent, {
					shot = sampled.shots[1],
					yaw = command.yaw,
					pitch = command.pitch,
					headYaw = command.headYaw,
					headPitch = command.headPitch,
				})
			end

			local moves: { any } = rig.moves
			local newest: any = moves[#moves]
			if newest then
				rig.owner(rig.body(FEET, newest.command, tick))
			end

			frame += 1
		end
	end

	step(BEFORE)
	mounted.shoot(AKM)
	local before: number = #sent
	step(FIRING)
	local fired: number = #sent

	-- 1) Firing: a shot's command looks along that shot, one between shots along the last, the head level
	local last: { [string]: number }? = nil
	local between: number = 0
	local aims: { [number]: boolean } = {} -- Each shot's yaw, so the last shot's look is told from the first's
	local distinct: number = 0

	for index: number = before + 1, fired do
		local command: Sent = sent[index]
		local shot: { [string]: number }? = command.shot
		local aim: { [string]: number }? = shot or last
		if aim == nil then
			return false, `Firing command {index - before} came before any shot`
		end

		if shot then
			if not aims[shot.yaw] then
				aims[shot.yaw] = true
				distinct += 1
			end

			last = shot
		else
			between += 1
		end

		local yaw: number = steps(command.yaw) % angleSteps
		local pitch: number = steps(command.pitch)
		if yaw ~= aim.yaw or pitch ~= aim.pitch then
			return false,
				`Firing command {index - before} looked along {yaw} and {pitch}, not {aim.yaw} and {aim.pitch}`
		elseif command.headYaw ~= 0 or command.headPitch ~= 0 then
			local offset: string = `{command.headYaw} and {command.headPitch}`
			return false, `Firing command {index - before} carried a head offset of {offset}, not 0`
		end
	end

	if fired - before < FIRING / 2 then
		return false, `{FIRING} frames of firing made {fired - before} commands`
	elseif between == 0 then
		return false, "No command came between two shots, so holding the last shot's look was never tried"
	elseif distinct < 2 then
		return false, "Every shot looked the same way, so the last shot's look was never told from the first's"
	end

	-- 2) Stopped: the camera's look and head offset again
	mounted.shoot(0)
	step(AFTER)

	if #sent == fired then
		return false, "No command was sent after shoot(0)"
	end

	for index: number = fired + 1, #sent do
		local command: Sent = sent[index]
		local yaw: number = steps(command.yaw) % angleSteps
		local pitch: number = steps(command.pitch)
		local headYaw: number = command.headYaw
		local headPitch: number = command.headPitch

		if yaw ~= steps(CAMERA_YAW) or pitch ~= steps(CAMERA_PITCH) then
			return false, `After shoot(0), command {index - fired} looked along {yaw} and {pitch}, not the camera's`
		elseif math.abs(headYaw - HEAD_YAW) > headStep or math.abs(headPitch - HEAD_PITCH) > headStep then
			return false, `After shoot(0), command {index - fired} carried a head offset of {headYaw} and {headPitch}`
		end
	end

	return true, nil
end
