--[[
    character:sleep turns the character into a sleeper in its slot, Invisible
    cleared, which getAll lists and sampleAt answers lying; destroy after it
    keeps the slot; sleeper:wake stands a new character up there with its
    history seeded lying and the epoch moved on; past the share sleep is nil
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local CLOSE: number = 0.1 -- Studs a sample may sit from the place it answers for

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local Slots: any = rig:require(rig.tread.Server.Slots)

	local viewerKey: any = rig.mock:addBot("Viewer")
	server:create(viewerKey, rig:at(0, 0))
	local sleepyKey: any = rig.mock:addBot("Sleepy")
	local character: any = server:create(sleepyKey, rig:at(6, 0))
	rig:tick(TICKS)

	character:setInvisible(true)
	local slot: number, generation: number = character._slot, character._generation
	local standing: any = character:getState().root
	local sleeper: any = character:sleep()
	local _, entry: any = Slots.get(slot)

	if not sleeper or sleeper._slot ~= slot or sleeper._generation ~= generation or entry.kind ~= "Sleeper" then
		return false, "The sleep made no sleeper keeping the character's slot and generation"
	elseif pcall(character.getState, character) then
		return false, "The character that slept still gave its state"
	end

	local all: { any } = server:getAll()
	if #all ~= 2 or not table.find(all, sleeper) or table.find(all, character) then
		return false, `getAll gave {#all} targets, not the viewer and the sleeper in place of the character`
	end

	-- Destroy after the sleep keeps the slot, which is the sleeper's
	character:destroy()
	local _, kept: any = Slots.get(slot)
	if not kept or kept.kind ~= "Sleeper" or Connections.get(sleepyKey) ~= nil then
		return false, "Destroy after the sleep took the sleeper's slot, or left the connection"
	end

	rig:tick(TICKS)

	local lying: any = server:sampleAt(sleeper, TICKS * 2)
	if not lying or lying.posture ~= "Downed" or (lying.position - standing).Magnitude > CLOSE then
		return false, "The sleeper's sample is not its Downed shapes where it lay down"
	elseif not Relay.isSent(viewerKey, slot) then
		return false, "The sleeper was not sent to the viewer, so its Invisible was not cleared"
	end

	-- The wake stands a character up in the same slot, its history seeded lying up to now
	local wokenKey: any = rig.mock:addBot("Woken")
	local woken: any = sleeper:wake(wokenKey)
	local _, awake: any = Slots.get(slot)

	if woken._slot ~= slot or woken._generation ~= generation or awake.kind ~= "Player" then
		return false, "The wake gave a character outside the sleeper's slot and life"
	elseif pcall(sleeper.wake, sleeper, rig.mock:addBot("Again")) or pcall(sleeper.destroy, sleeper) then
		return false, "A woken sleeper took a second wake or a destroy"
	end

	local seeded: any = server:sampleAt(woken, TICKS * 2)
	if not seeded or seeded.posture ~= "Downed" then
		return false, "The woken character's history holds no lying sample at the wake"
	end

	local seedEpoch: number = seeded.epoch
	rig:tick(TICKS)

	local after: any = server:sampleAt(woken, TICKS * 3)
	if not after or after.posture == "Downed" or after.epoch == seedEpoch then
		return false, "The woken character's history after the wake is still lying, or kept the epoch"
	elseif woken:getState().posture == "Downed" then
		return false, "The woken character never stood up"
	end

	-- Past the sleepers' share a sleep gives nil and is reported, and the character carries on
	local full: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.slots.reserve = 4096
	end)

	local fullServer: any = full:start()
	local awakeCharacter: any = fullServer:create(full.mock:addBot("Awake"), full:at(0, 0))

	if awakeCharacter:sleep() ~= nil or #full:reported("sleep") ~= 1 then
		return false, "A sleep past the share gave a sleeper or no sleep report"
	elseif awakeCharacter:getState() == nil then
		return false, "The refused sleep ended the character"
	end

	return true, nil
end
