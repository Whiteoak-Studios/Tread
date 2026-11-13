--[[
    character:die lays a body in a slot of its own wearing the character's
    look and sends the death, with both ids and the push, to the viewers
    sent it and its own player; the character leaves at once, destroy after
    it releases the rest, and npc:die and body:destroy end theirs alike
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local HEAD: number = 12 -- An item index the example's head slot holds
local STEPS: number = 127 -- A push component's steps for a whole unit

type Death = { character: number, body: number, x: number, y: number, z: number }

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Connections: any = rig:require(rig.tread.Server.Connections)
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)
	local Record: any = rig:require(rig.tread.Codec.Record)
	local Relay: any = rig:require(rig.tread.Server.Relay)
	local Slots: any = rig:require(rig.tread.Server.Slots)

	local client: any = rig:require(rig.tread.Network.Client)
	local viewerKey: any = rig.mock.players[1]
	local deaths: { Death } = {}

	client.Death.on(function (character: number, body: number, x: number, y: number, z: number)
		table.insert(deaths, { character = character, body = body, x = x, y = y, z = z })
	end)

	client.flush()
	rig:deliver()

	local viewer: any = server:create(viewerKey, rig:at(0, 0))
	local victimKey: any = rig.mock:addBot("Victim")
	local victim: any = server:create(victimKey, rig:at(6, 0))
	victim:setOutfit({ head = HEAD })
	rig:tick(TICKS)

	if pcall(victim.die, victim, "east") then
		return false, "character:die took a string for its push"
	end

	local slot: number, generation: number = victim._slot, victim._generation
	local body: any = victim:die(roblox.Vector3.new(2, 0, 0))
	local _, entry: any = Slots.get(body._slot)

	if body._slot == slot or not entry or entry.kind ~= "Body" then
		return false, "The death laid no body in a slot of its own"
	elseif #server:getAll() ~= 1 or server:sampleAt(victim, TICKS) ~= nil or pcall(victim.getState, victim) then
		return false, "The dead character stayed in getAll, the history or getState"
	end

	rig:tick(TICKS)
	rig:deliver()

	local death: Death? = deaths[1]
	if not death or death.character ~= Record.id(slot, generation) then
		return false, `The viewer heard {#deaths} deaths, none naming the victim`
	elseif death.body ~= Record.id(body._slot, body._generation) or death.x ~= STEPS or death.y ~= 0 then
		return false, `The death named body {death.body} with a push of {death.x}, {death.y}, {death.z}`
	elseif Relay.isSent(viewerKey, slot) or not Relay.isSent(viewerKey, body._slot) then
		return false, "The viewer was still sent the victim, or never sent its body"
	end

	local keyframe: any = Keyframe.read(server:keyframe(viewerKey))
	local seen: any = keyframe.characters[1]
	if #keyframe.characters ~= 1 or seen.kind ~= "Body" or buffer.len(seen.look) == 0 then
		return false, "The viewer's keyframe holds no body wearing the victim's look"
	end

	-- Destroy after the death releases the slot and the connection, and never errors
	victim:destroy()
	local _, released: any = Slots.get(slot)
	if released ~= nil or Connections.get(victimKey) ~= nil then
		return false, "Destroy after the death left the character's slot or connection"
	elseif pcall(victim.destroy, victim) then
		return false, "A second destroy was taken"
	end

	-- An NPC's death, with no push, and its destroy after
	local npc: any = server:createNpc(rig:at(-6, 0))
	rig:tick(TICKS)
	local npcSlot: number = npc._slot
	local npcBody: any = npc:die(nil)
	npc:destroy()
	rig:tick(1)
	rig:deliver()

	local npcDeath: Death? = deaths[2]
	local _, npcEntry: any = Slots.get(npcSlot)
	if not npcDeath or npcDeath.body ~= Record.id(npcBody._slot, npcBody._generation) or npcDeath.x ~= 0 then
		return false, "The NPC's death reached the viewer with no body or a push"
	elseif npcEntry ~= nil then
		return false, "The dead NPC's slot is still taken"
	elseif pcall(npc.destroy, npc) then
		return false, "A second npc:destroy was taken"
	end

	-- Each body leaves on its destroy
	body:destroy()
	npcBody:destroy()

	local _, bodyEntry: any = Slots.get(body._slot)
	if bodyEntry ~= nil or pcall(body.destroy, body) then
		return false, "A destroyed body kept its slot, or took a second destroy"
	end

	-- A character's own player hears its death too
	viewer:die(nil)
	rig:tick(1)
	rig:deliver()

	local own: Death? = deaths[3]
	if not own or own.character ~= Record.id(viewer._slot, viewer._generation) then
		return false, "The dying character's own player heard no death of it"
	end

	return true, nil
end
