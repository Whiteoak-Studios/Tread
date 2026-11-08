--[[
    A sleeper past the sleepers' share gets nil and a sleep past it is
    refused with nothing changed, a body that finds no slot free errors
    naming the reserve, and a slot's next sleeper reuses its state, reset
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local SLOTS: number = 4096 -- The character slots every kind shares
local SHARE: number = 2 -- The sleepers the reserve below leaves room for
local BED: vector = vector.create(0, 2, 0)
local OTHER_BED: vector = vector.create(50, 4, -50)

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
	server.slots.reserve = SLOTS - SHARE
	Slots.start(server.slots.reserve)
	History.start(shared, server)
	Sleepers.start(shared)

	-- 1) The share's sleepers fit, and the next gets nil with no slot taken
	local first: number?, firstGeneration: number?, firstState: any = Sleepers.create("Sleeper", BED, 0)
	local second: number? = Sleepers.create("Sleeper", BED, 0)
	local past: number?, pastGeneration: number?, pastState: any = Sleepers.create("Sleeper", BED, 0)

	if first == nil or second == nil then
		return false, "A sleeper inside the share got no slot"
	elseif past ~= nil or pastGeneration ~= nil or pastState ~= nil then
		return false, `A sleeper past the share got slot {past}, generation {pastGeneration}`
	elseif Slots.count("Sleeper") ~= SHARE then
		return false, `The refused sleeper left {Slots.count("Sleeper")} sleepers held, not {SHARE}`
	end

	-- 2) A sleep past the share is refused, the character's slot and state left as they were
	local character: number = Slots.take("Player")
	Slots.setEntry(character, { kind = "Player", rig = "A" })

	local awake: any = State.new()
	awake.posture = "Crouch"

	if Sleepers.adopt(character, awake) ~= false then
		return false, "A sleep past the share was not refused"
	elseif select(2, Slots.get(character)).kind ~= "Player" then
		return false, "A refused sleep changed the character's entry"
	elseif awake.posture ~= "Crouch" or Slots.count("Sleeper") ~= SHARE then
		return false, `A refused sleep laid the state down, or left {Slots.count("Sleeper")} sleepers held`
	end

	local ok: boolean, reason: any = pcall(Sleepers.sampleAt, character, 0)
	if ok or not string.find(`{reason}`, "holds neither", 1, true) then
		return false, `A refused sleep's slot still answered as a sleeper: {reason}`
	end

	-- 3) Bodies take every slot left, and the next one errors naming the reserve
	for _ = 1, SLOTS - SHARE - 1 do
		Sleepers.create("Body", BED, 0)
	end

	local made: boolean, refusal: any = pcall(Sleepers.create, "Body", BED, 0)
	if made then
		return false, "A body found a slot in a full table"
	elseif not string.find(`{refusal}`, `slots.reserve holds back {SLOTS - SHARE}`, 1, true) then
		return false, `A body with no slot free errored without naming the reserve: {refusal}`
	elseif Sleepers.create("Sleeper", BED, 0) ~= nil then
		return false, "A sleeper found a slot in a full table"
	end

	-- 4) A slot given out again reuses the state its last sleeper lay in, reset to a fresh life's
	firstState.epoch = 5
	firstState.held.item = 3
	firstState.fields.revived = true
	Sleepers.remove(first)

	local again: number?, againGeneration: number?, againState: any = Sleepers.create("Sleeper", OTHER_BED, 1)
	if again ~= first or againGeneration ~= (firstGeneration :: number) + 1 then
		return false, `The one free slot gave slot {again} generation {againGeneration}, not {first}'s next`
	elseif againState ~= firstState then
		return false, "The slot's next sleeper was built a new state"
	elseif againState.epoch ~= 0 or next(againState.held) ~= nil or next(againState.fields) ~= nil then
		return false, `The reused state kept epoch {againState.epoch}, or the last life's game values`
	elseif againState.position ~= OTHER_BED or againState.posture ~= "Downed" then
		return false, `The reused state lay at {againState.position} in {againState.posture}`
	end

	return true, nil
end
