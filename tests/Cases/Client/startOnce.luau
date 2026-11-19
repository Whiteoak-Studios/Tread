--[[
    Requiring the client handle loads no Volt module, a start with a wrong
    setting refuses it naming the key before anything starts, a good start
    sends the scope's handshake at once, and a second start is refused
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local MISSING: string = "client.drawDistance expected a table"

return function (): (boolean, string | nil)
	local rig: any = Handle.new({ start = false })
	local mock: any = rig.mock

	if #mock.players ~= 0 then
		return false, `Requiring the client handle joined {#mock.players} players, so it loaded Volt's client module`
	end

	local handshakes: number = 0
	rig.server.onHandshake(function (_: any)
		handshakes += 1
	end)

	local distances: any = rig.client.drawDistance
	rig.client.drawDistance = nil

	local refused: boolean, failure: any = pcall(rig.Client.start, rig.shared, rig.client)
	if refused then
		return false, "A start with no draw distances was taken"
	elseif string.find(tostring(failure), MISSING, 1, true) ~= 1 then
		return false, `A start with no draw distances failed as "{failure}", not naming the key`
	elseif #mock.players ~= 0 or rig.pool.made ~= 0 then
		return false, "A refused start still loaded Volt's client module or built the rig pool"
	end

	rig.client.drawDistance = distances
	rig.start()

	-- The server tells a handshake once its own flush has sent what it held for the player
	rig.server.flush()
	rig.step()

	if #mock.players ~= 1 then
		return false, `A start joined {#mock.players} players to the mock, not 1`
	elseif handshakes ~= 1 then
		return false, `The server heard {handshakes} handshakes after the start, where the start flushes 1`
	elseif rig.pool.made ~= 1 then
		return false, `A start built the rig pool {rig.pool.made} times, not once`
	end

	local again: boolean, reason: any = pcall(rig.Client.start, rig.shared, rig.client)
	if again then
		return false, "A second start was taken"
	elseif not string.find(tostring(reason), "starts once", 1, true) then
		return false, `A second start failed as "{reason}", not as a second start`
	end

	return true, nil
end
