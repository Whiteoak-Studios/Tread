--[[
    The dev game's forward-only sprint flag: on, as the module ships, only a
    move straight ahead sprints; off, a strafe, a diagonal and a backward move
    sprint too, while aiming and the post-shot lock still refuse it
--]]

--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Harness = require("../../Fixtures/DevShared/Harness")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SOURCE: string = "dev/Shared/Config.luau"
local FLAG_ON: string = "local FORWARD_ONLY_SPRINT: boolean = true"
local FLAG_OFF: string = "local FORWARD_ONLY_SPRINT: boolean = false"
local CONTENT: string = "TestContent"
local DATATYPE: string = "^%u" -- A name Lune's library holds a Roblox datatype or Instance under
local AIM_SPEED: number = 8 -- Studs/s aiming with an item that sets none
local SHOT: { [string]: number } = { sequence = 1, class = 0, renderTick = 0, fraction = 0, yaw = 0, pitch = 0 }
local SETTLED: number = 100 -- Ground ticks well past the landing lock

type Rules = (step: { [string]: any }, allow: { [string]: boolean }) -> number

-- A move by its axes, and whether the flag's rule lets it sprint
type Heading = { label: string, forward: number, right: number, forwardOnly: boolean }

local HEADINGS: { Heading } = {
	{ label = "straight ahead", forward = 1, right = 0, forwardOnly = true },
	{ label = "a strafe", forward = 0, right = 1, forwardOnly = false },
	{ label = "a diagonal", forward = 1, right = -1, forwardOnly = false },
	{ label = "backward", forward = -1, right = 0, forwardOnly = false },
}

-- A character settled on the ground, sprint held, its rule timers past their locks, moving by the axes given
local function newStep(forward: number, right: number): { [string]: any }
	local pressed: { [string]: boolean } = { jump = false, crouch = false, sprint = false, aim = false }

	return {
		command = {
			number = 0,
			forward = forward,
			right = right,
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
		block = { sinceJump = 15, sinceShot = 15 },
		isNpc = false,
	}
end

-- Whether the rules let a step sprint, with everything Tread's physics permits
local function sprints(rules: Rules, step: { [string]: any }): (boolean, number)
	local allow: { [string]: boolean } = { jump = true, sprint = true, crouch = true, stand = true }
	local cap: number = rules(step, allow)

	return allow.sprint, cap
end

--[[
    The dev module's rules with its flag off: its own source with the flag's
    one line changed, run as the harness runs it, in a fresh game with Tread
    and the test content folder
--]]

local function flagOff(): (Rules?, string?)
	local source: string = fs.readFile(SOURCE)
	local start: number?, finish: number? = string.find(source, FLAG_ON, 1, true)
	if not start or not finish or string.find(source, FLAG_ON, finish + 1, true) then
		return nil, `{SOURCE} holds "{FLAG_ON}" other than once`
	end

	local patched: string = `{source:sub(1, start - 1)}{FLAG_OFF}{source:sub(finish + 1)}`
	local globals: any = Environment.load(GLOBALS)
	local dataModel: any = globals.game

	local content: any = roblox.Instance.new("Folder")
	content.Name = CONTENT
	content.Parent = dataModel:GetService("Workspace")

	local scope: { [string]: any } = { game = dataModel, require = globals.require }
	for name: string, value: any in roblox do
		if name:match(DATATYPE) then
			scope[name] = value
		end
	end

	local chunk: () -> any = luau.load(patched, { debugName = SOURCE, environment = scope })

	return chunk().rules, nil
end

return function (): (boolean, string | nil)
	local on: Rules = Harness.load().shared.rules
	local off: Rules?, failure: string? = flagOff()
	if not off then
		return false, failure
	end

	for _, heading: Heading in HEADINGS do
		local onSprints: boolean = sprints(on, newStep(heading.forward, heading.right))
		if onSprints ~= heading.forwardOnly then
			return false, `With the flag on, a sprint {heading.label} was allowed {onSprints}`
		end

		local offSprints: boolean = sprints(off, newStep(heading.forward, heading.right))
		if not offSprints then
			return false, `With the flag off, a sprint {heading.label} was refused`
		end
	end

	-- Off, aiming still refuses a strafe's sprint and caps the speed, and a shot still locks it
	local aiming: { [string]: any } = newStep(0, 1)
	aiming.command.aim = true
	local aimSprints: boolean, aimCap: number = sprints(off, aiming)
	if aimSprints or aimCap ~= AIM_SPEED then
		return false, `With the flag off, an aimed strafe gave sprint {aimSprints} and a cap of {aimCap}`
	end

	local shooting: { [string]: any } = newStep(-1, 0)
	shooting.command.fields.shots = { SHOT }
	local shotSprints: boolean = sprints(off, shooting)
	if shotSprints then
		return false, "With the flag off, a backward move sprinted through the post-shot lock"
	end

	return true, nil
end
