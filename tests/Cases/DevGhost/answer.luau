--[[
    An ask is answered, in its own order, with the feet and velocity of
    each asked slot the asker is sent that holds another player's or bot's
    character: an unsent slot, an NPC, the asker's own slot, a free slot
    and one past the slot table get no ghost
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/DevGhost/Harness")

local START: number = 1790000000 -- The server's clock at the case's first frame, seconds
local FRAME: number = 1 / 60

local OWN: number = 1 -- The asker's own character
local SENT: number = 2 -- Another player's character the asker is sent
local UNSENT: number = 3 -- And one it isn't
local NPC: number = 4 -- An NPC, which the relay sends every viewer in range
local BOT: number = 5 -- A bot's character the asker is sent
local FREE: number = 9 -- A slot nothing holds
local PAST: number = 65535 -- A u16 past the slot table's 4,096 slots, as a spoofed ask could carry

-- Inside the wire bounds, each a value a float32 holds exactly
local SENT_ROOT: any = roblox.Vector3.new(120.5, 3.25, -40.75)
local SENT_VELOCITY: any = roblox.Vector3.new(16, -2.5, 0.125)
local BOT_ROOT: any = roblox.Vector3.new(-310.25, 0, 77.5)
local BOT_VELOCITY: any = roblox.Vector3.new(0, 0, -24)
local ELSEWHERE: any = roblox.Vector3.new(500, 10, 500) -- Where every other character stands, still
local STILL: any = roblox.Vector3.new(0, 0, 0)

local function player(name: string): any
	local made: any = roblox.Instance.new("Player")
	made.Name = name

	return made
end

-- Whether a ghost holds a slot and the feet and velocity it stood at, field by field
local function matches(ghost: any, slot: number, root: any, velocity: any): boolean
	return ghost ~= nil
		and ghost.slot == slot
		and ghost.x == root.X
		and ghost.y == root.Y
		and ghost.z == root.Z
		and ghost.vx == velocity.X
		and ghost.vy == velocity.Y
		and ghost.vz == velocity.Z
end

return function (): (boolean, string | nil)
	local rig: Harness.Rig = Harness.load()
	local asker: any = player("Asker")

	-- A Volt bot's key is no Player, and Tread's character names it as its player all the same
	local bot: any = { Name = "Bot" }

	rig.character(asker, OWN, ELSEWHERE, STILL)
	rig.character(player("Seen"), SENT, SENT_ROOT, SENT_VELOCITY)
	rig.character(player("Unseen"), UNSENT, ELSEWHERE, STILL)
	rig.npc(NPC, ELSEWHERE, STILL)
	rig.character(bot, BOT, BOT_ROOT, BOT_VELOCITY)

	-- Its own slot, the NPC and the free slot marked sent too, so only the module's own checks leave them out
	rig.sentTo[asker] = { [OWN] = true, [SENT] = true, [NPC] = true, [BOT] = true, [FREE] = true }

	rig.ask(asker, { SENT, UNSENT, NPC, OWN, FREE, PAST, BOT })
	rig.frame(START)
	rig.state.ran += 1
	rig.frame(START + FRAME)

	local sent: Harness.Sent? = rig.sent[1]
	if #rig.sent ~= 1 or not sent then
		return false, `A tick sent the asker {#rig.sent} times, not once`
	end

	local slots: { string } = {}
	for _, ghost: any in sent.ghosts do
		table.insert(slots, tostring(ghost.slot))
	end

	local named: string = table.concat(slots, ", ")
	if #sent.ghosts ~= 2 then
		return false, `The ask was answered for the slots {named}, not {SENT} and {BOT}`
	elseif not matches(sent.ghosts[1], SENT, SENT_ROOT, SENT_VELOCITY) then
		return false, `The first ghost was not slot {SENT} at its feet and velocity, of the slots {named}`
	elseif not matches(sent.ghosts[2], BOT, BOT_ROOT, BOT_VELOCITY) then
		return false, `The second ghost was not the bot's slot {BOT} at its feet and velocity, of the slots {named}`
	end

	return true, nil
end
