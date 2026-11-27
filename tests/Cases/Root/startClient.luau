--[[
    Tread.startClient starts the client's handle over Volt.mock: a refused
    table names its key, the handle it gives is the client's, its handshake
    goes out at once, its own character's state arrives on Vector3, and a
    second start is refused
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../../Fixtures/Client/Handle")

local MISSING: string = "client.drawDistance expected a table"
local SLOT: number = 12
local GENERATION: number = 1
local COMMAND: number = 40
local TICK: number = 300
local HEADROOM: number = 1e-6 -- How far a float32 Vector3 may sit from the vector it was copied from

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })
	local Tread: any = rig.globals.require(rig.tread)

	local handshakes: number = 0
	rig.server.onHandshake(function (_: any)
		handshakes += 1
	end)

	local distances: any = rig.client.drawDistance
	rig.client.drawDistance = nil

	local refused: boolean, failure: any = pcall(Tread.startClient, rig.shared, rig.client)
	if refused then
		return false, "Tread.startClient took client settings with no draw distances"
	elseif string.find(tostring(failure), MISSING, 1, true) ~= 1 then
		return false, `Tread.startClient's refusal failed as "{failure}", not naming the key`
	end

	rig.client.drawDistance = distances
	local handle: any = Tread.startClient(rig.shared, rig.client)
	if getmetatable(handle) ~= rig.Client then
		return false, "Tread.startClient gave something other than the client's handle"
	end

	rig.step()
	rig.server.flush()
	rig.step()

	if handshakes ~= 1 then
		return false, `The server heard {handshakes} handshakes after Tread.startClient, not 1`
	end

	local at: vector = vector.create(10, 20, -30)
	rig.handshake()
	rig.own(SLOT, GENERATION)
	rig.owner(rig.body(at, COMMAND, TICK))

	local state: any = handle:getState()
	if state == nil then
		return false, "Its own slot's first OwnerState left the client with no state"
	elseif typeof(state.root) ~= "Vector3" then
		return false, `The client's state gave its root as a {typeof(state.root)}, not a Vector3`
	elseif (state.root - roblox.Vector3.new(at.x, at.y, at.z)).Magnitude > HEADROOM then
		return false, `The client's state stands at {state.root}, where the OwnerState put the body at {at}`
	end

	if pcall(Tread.startClient, rig.shared, rig.client) then
		return false, "A second Tread.startClient was taken"
	end

	return true, nil
end
