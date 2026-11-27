--[[
    getEye gives the eye and look the frame found: calls between two frames
    make no cast through the client's world and all give the same answer
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local SLOT: number = 12
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local CALLS: number = 5

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle

	rig.handshake()
	rig.own(SLOT, GENERATION)
	rig.owner(rig.body(vector.create(10, 20, -30), COMMAND, TICK))
	rig.frames(1)

	-- Every cast the world makes from here on is counted, each still answered by the one it stands in front of
	local world: any = handle._world
	local casts: number = 0
	local counted: { [string]: any } = {}
	for name: string, cast: any in world.collision do
		counted[name] = function (...: any): ...any
			casts += 1

			return cast(...)
		end
	end
	world.collision = counted

	local eye: any, look: any = handle:getEye()
	for call: number = 2, CALLS do
		local again: any, along: any = handle:getEye()
		if again ~= eye or along ~= look then
			return false, `Call {call} gave {again} looking {along}, where the first gave {eye} looking {look}`
		end
	end

	if casts ~= 0 then
		return false, `{CALLS} calls between two frames made {casts} casts`
	end

	-- The next frame finds its eye through the world, so the count would see a call's casts
	rig.frames(1)
	if casts == 0 then
		return false, "A frame drew the owner's body and eye with no cast the count saw"
	end

	return true, nil
end
