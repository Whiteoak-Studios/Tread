--[[
    A created sleeper and body and an adopted character each lie Downed in
    Ground, grounded at rest, walking, with no lean, sprint, aim, platform,
    ladder or held item, each slot's entry naming its kind and rig
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local EYE_STEPS: number = 32 -- OwnerState's eye height steps a stud
local BED: vector = vector.create(10, 5, -20)
local BED_YAW: number = 1.2
local GRAVE: vector = vector.create(-4, 2, 7)
local GRAVE_YAW: number = -0.5
local CHAIR: vector = vector.create(3, 9, 3) -- Where the adopted character was when it fell asleep
local CHAIR_YAW: number = 2.5
local EPOCH: number = 7 -- The adopted character's, which its sleep keeps

-- Why a state does not lie at the place and yaw, or nil when it does
local function lying(state: any, position: vector, yaw: number, eye: number): string?
	local expected: { [string]: any } = {
		position = position,
		velocity = vector.zero,
		facing = yaw,
		mode = "Ground",
		posture = "Downed",
		sprint = false,
		aim = false,
		platform = 0,
		moveMode = "Walk",
		grounded = true,
		lean = 0,
		eyeHeight = eye,
		apex = position.y,
		groundHeight = position.y,
		mantleTicks = 0,
		mantleRise = 0,
		ladder = 0,
	}

	for field: string, value: any in expected do
		if state[field] ~= value then
			return `its {field} was {state[field]}, not {value}`
		end
	end

	if next(state.held) ~= nil then
		return "it still held an item"
	end

	return nil
end

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Example: any = globals.require(globals.game:GetService("ServerScriptService").Fixtures.Config.Example)
	local History: any = globals.require(tread.Server.History)
	local Sleepers: any = globals.require(tread.Server.Sleepers)
	local Slots: any = globals.require(tread.Server.Slots)
	local State: any = globals.require(tread.Step.State)

	local shared: any = Example.shared()
	local server: any = Example.server()
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared)

	local eye: number = math.round(shared.step.eyeDowned * EYE_STEPS) / EYE_STEPS

	-- 1) A sleeper and a body, each in a slot of its own with its first generation
	local sleeper: number?, sleeperGeneration: number?, sleeperState: any = Sleepers.create("Sleeper", BED, BED_YAW)
	local body: number?, bodyGeneration: number?, bodyState: any = Sleepers.create("Body", GRAVE, GRAVE_YAW)
	if sleeper == nil or body == nil or sleeper == body then
		return false, `The sleeper and the body took slots {sleeper} and {body}`
	elseif sleeperGeneration ~= 1 or bodyGeneration ~= 1 then
		return false, `New slots carried generations {sleeperGeneration} and {bodyGeneration}, not their first, 1`
	elseif sleeperState == bodyState then
		return false, "The sleeper and the body shared one state"
	end

	local made: { { name: string, slot: number, state: any, at: vector, yaw: number, kind: string } } = {
		{ name = "sleeper", slot = sleeper, state = sleeperState, at = BED, yaw = BED_YAW, kind = "Sleeper" },
		{ name = "body", slot = body, state = bodyState, at = GRAVE, yaw = GRAVE_YAW, kind = "Body" },
	}

	for _, one in made do
		local why: string? = lying(one.state, one.at, one.yaw, eye)
		local generation: number, entry: any = Slots.get(one.slot)

		if why then
			return false, `The created {one.name} did not lie: {why}`
		elseif generation ~= 1 or entry == nil or entry.kind ~= one.kind or entry.rig ~= "A" or entry.player ~= nil then
			return false, `The {one.name}'s slot held generation {generation} and {entry and entry.kind}, not its own`
		elseif one.state.epoch ~= 0 or next(one.state.fields) ~= nil or next(one.state.block) ~= nil then
			return false, `The created {one.name} started at epoch {one.state.epoch}, or with game values set`
		end
	end

	-- 2) A character falls asleep in its own slot, keeping its generation, rig and epoch, its state laid down in place
	local slot: number, generation: number = Slots.take("Player")
	Slots.setEntry(slot, { kind = "Player", rig = "B" })

	local state: any = State.new()
	state.position = CHAIR
	state.velocity = vector.create(4, -2, 1)
	state.facing = CHAIR_YAW
	state.mode = "Air"
	state.posture = "Crouch"
	state.sprint = true
	state.aim = true
	state.platform = 3
	state.moveMode = "Noclip"
	state.lean = 12
	state.mantleTicks = 4
	state.ladder = 2
	state.epoch = EPOCH
	state.held.item = 5

	if Sleepers.adopt(slot, state) ~= true then
		return false, "A character inside the sleepers' share could not fall asleep"
	end

	local why: string? = lying(state, CHAIR, CHAIR_YAW, eye)
	local kept: number, entry: any = Slots.get(slot)

	if why then
		return false, `The adopted character did not lie: {why}`
	elseif kept ~= generation then
		return false, `The sleep moved the slot's generation from {generation} to {kept}`
	elseif entry.kind ~= "Sleeper" or entry.rig ~= "B" or entry.player ~= nil then
		return false, `The sleeper's entry read {entry.kind} with rig {entry.rig}, not a Sleeper keeping rig B`
	elseif state.epoch ~= EPOCH then
		return false, `The sleep changed the epoch from {EPOCH} to {state.epoch}`
	elseif Slots.count("Sleeper") ~= 2 or Slots.count("Player") ~= 0 or Slots.count("Body") ~= 1 then
		return false, `The slot table counted {Slots.count("Sleeper")} sleepers and {Slots.count("Player")} players`
	end

	-- 3) The adopted sleeper is hit lying where it fell asleep, in its own epoch
	local sample: any = Sleepers.sampleAt(slot, 0)
	if sample.position ~= CHAIR or sample.posture ~= "Downed" or sample.epoch ~= EPOCH then
		return false, `The adopted sleeper was hit at {sample.position} in {sample.posture}, epoch {sample.epoch}`
	end

	return true, nil
end
