--[[
    The dev game's rules are Frontier Zero's: the jump cooldown from a new
    character, coyote time and the landing lock, forward-only sprint and its
    post-shot lock, the aim speed, and the downed crawl that a revive stops
--]]

--!strict
local Harness = require("../../Fixtures/DevShared/Harness")

local COOLDOWN_TICKS: number = 10 -- Frontier Zero's 0.5 s jump cooldown and post-shot lock at 20 Hz
local COYOTE_TICKS: number = 2 -- Its 0.1 s of coyote time at 20 Hz
local LANDING_TICKS: number = 2 -- Its 0.1 s landing lock at 20 Hz
local AIM_SPEED: number = 8 -- Studs/s aiming with an item that sets none
local CRAWL_SPEED: number = 2 -- Studs/s a downed body crawls at
local SETTLED: number = 100 -- Ground ticks well past the landing lock
local SHOT: { [string]: number } = { sequence = 1, class = 0, renderTick = 0, fraction = 0, yaw = 0, pitch = 0 }

type Rules = (step: { [string]: any }, allow: { [string]: boolean }) -> number

-- A new character standing on the ground, walking forward with sprint held and nothing pressed
local function newStep(): { [string]: any }
	local pressed: { [string]: boolean } = { jump = false, crouch = false, sprint = false, aim = false }

	return {
		command = {
			number = 0,
			forward = 1,
			right = 0,
			jump = false,
			crouch = false,
			sprint = true,
			aim = false,
			pressed = pressed,
			yaw = 0,
			pitch = 0,
			lean = 0,
			headYaw = 0,
			headPitch = 0,
			fields = { slot = 0, shots = {} },
		},

		pressed = pressed,
		grounded = true,
		mode = "Ground",
		posture = "Stand",
		airTicks = 0,
		groundTicks = SETTLED,
		fields = { beingRevived = false },
		held = {},
		block = { sinceJump = 0, sinceShot = 15 }, -- The declarations' starts
		isNpc = false,
	}
end

-- Runs the rules once on what Tread's physics permits, everything unless jump is given
local function run(rules: Rules, step: { [string]: any }, jump: boolean?): (number, { [string]: boolean })
	local allow: { [string]: boolean } = { jump = jump ~= false, sprint = true, crouch = true, stand = true }
	local cap: number = rules(step, allow)

	return cap, allow
end

return function (): (boolean, string | nil)
	local rules: Rules = Harness.load().shared.rules

	-- A new character's first jump waits out the cooldown, and a jump starts it again
	local fresh: { [string]: any } = newStep()
	fresh.pressed.jump = true

	for tick: number = 1, COOLDOWN_TICKS do
		local _, allow: { [string]: boolean } = run(rules, fresh)
		if allow.jump ~= (tick == COOLDOWN_TICKS) then
			return false, `A new character's jump on tick {tick} was allowed {allow.jump}`
		end
	end

	if fresh.block.sinceJump ~= 0 then
		return false, `A jump left the cooldown at {fresh.block.sinceJump}`
	end

	-- Coyote time off a ledge, where Tread itself permits no jump
	for airTicks: number = COYOTE_TICKS, COYOTE_TICKS + 1 do
		local step: { [string]: any } = newStep()
		step.block.sinceJump = COOLDOWN_TICKS
		step.grounded = false
		step.mode = "Air"
		step.airTicks = airTicks

		local _, allow: { [string]: boolean } = run(rules, step, false)
		if allow.jump ~= (airTicks == COYOTE_TICKS) then
			return false, `A jump {airTicks} ticks off the ground was allowed {allow.jump}`
		end
	end

	-- The lock just after landing
	for groundTicks: number = LANDING_TICKS - 1, LANDING_TICKS do
		local step: { [string]: any } = newStep()
		step.block.sinceJump = COOLDOWN_TICKS
		step.groundTicks = groundTicks

		local _, allow: { [string]: boolean } = run(rules, step)
		if allow.jump ~= (groundTicks == LANDING_TICKS) then
			return false, `A jump {groundTicks} ticks after landing was allowed {allow.jump}`
		end
	end

	-- Sprint forward only, and never while aiming, which caps the speed instead
	local forward: { [string]: any } = newStep()
	local cap: number, allow: { [string]: boolean } = run(rules, forward)
	if not allow.sprint or cap ~= math.huge then
		return false, `Sprinting straight forward gave sprint {allow.sprint} and a cap of {cap}`
	end

	local strafe: { [string]: any } = newStep()
	strafe.command.right = 1
	local _, strafed: { [string]: boolean } = run(rules, strafe)
	if strafed.sprint then
		return false, "A sprint with a side direction held was allowed"
	end

	local aiming: { [string]: any } = newStep()
	aiming.command.aim = true
	local aimCap: number, aimed: { [string]: boolean } = run(rules, aiming)
	if aimed.sprint or aimCap ~= AIM_SPEED then
		return false, `Aiming gave sprint {aimed.sprint} and a cap of {aimCap}`
	end

	-- A shot locks sprint for the cooldown's ticks
	local shooting: { [string]: any } = newStep()
	shooting.command.fields.shots = { SHOT }

	local _, shot: { [string]: boolean } = run(rules, shooting)
	if shot.sprint or shooting.block.sinceShot ~= 0 then
		return false, `A shot left sprint {shot.sprint} and its timer at {shooting.block.sinceShot}`
	end

	shooting.command.fields.shots = {}
	for tick: number = 1, COOLDOWN_TICKS do
		local _, after: { [string]: boolean } = run(rules, shooting)
		if after.sprint ~= (tick == COOLDOWN_TICKS) then
			return false, `A sprint {tick} ticks after a shot was allowed {after.sprint}`
		end
	end

	-- Downed: a crawl, nothing else permitted, and no move at all while being revived
	local downed: { [string]: any } = newStep()
	downed.posture = "Downed"
	local crawl: number, refused: { [string]: boolean } = run(rules, downed)
	if crawl ~= CRAWL_SPEED or refused.jump or refused.sprint or refused.crouch or refused.stand then
		return false, `Downed gave a cap of {crawl} with jump {refused.jump} or a posture change still permitted`
	end

	downed.fields.beingRevived = true
	local revived: number = run(rules, downed)
	if revived ~= 0 then
		return false, `Being revived gave a cap of {revived}`
	end

	-- An NPC's command may carry no declared fields at all
	local npc: { [string]: any } = newStep()
	npc.command.fields = {}
	npc.isNpc = true
	local ran: boolean, npcCap: any = pcall(rules, npc, { jump = true, sprint = true, crouch = true, stand = true })
	if not ran or npcCap ~= math.huge then
		return false, `An NPC's command with no fields gave {npcCap}`
	end

	return true, nil
end
