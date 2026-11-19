--[[
    setRenderDistance refuses anything but a finite number above 0. Before
    the handshake it only keeps the value, which the server hears once the
    handshake passes; after it each call sends its value rounded up, held
    to 65,535, and the rig pool draws to each new distance
--]]

--!strict
local Handle = require("../../Fixtures/Client/Handle")

local OWN: number = 9
local GENERATION: number = 1
local TICK: number = 100
local FRAMES: number = 3 -- Enough for a Move, and the flush that carries View with it
local FARTHEST: number = 65535 -- The farthest render distance View's u16 carries
local KEPT: number = 400.2 -- Set before the handshake, and heard rounded up after it

local REFUSED: { any } = { 0, -400, 0 / 0, math.huge, -math.huge, "400", false }

-- Each later call's value, and what the server hears of it
local CALLS: { { number } } = {
	{ 700.5, 701 },
	{ 250, 250 },
	{ 100000, FARTHEST },
}

return function (): (boolean, string | nil)
	local rig: any = Handle.new()
	local handle: any = rig.handle
	local pool: any = rig.pool
	local start: number = pool.drawDistance
	local heard: { number } = {}

	rig.server.View.on(function (_: any, distance: number)
		table.insert(heard, distance)
	end)

	for _, value: any in REFUSED do
		local taken: boolean, failure: any = pcall(handle.setRenderDistance, handle, value)
		if taken then
			return false, `setRenderDistance took {value}`
		elseif not string.find(tostring(failure), "client:setRenderDistance takes", 1, true) then
			return false, `setRenderDistance refused {value} as "{failure}"`
		elseif pool.drawDistance ~= start then
			return false, `A refused {value} moved the pool's draw distance to {pool.drawDistance}`
		end
	end

	-- 1) Before the handshake the value is only kept, and drawn to
	handle:setRenderDistance(KEPT)
	if pool.drawDistance ~= KEPT then
		return false, `The pool draws to {pool.drawDistance} studs, not the {KEPT} set before the handshake`
	end

	-- 2) The handshake sends it once, with the first Move's flush
	rig.handshake()
	rig.own(OWN, GENERATION)
	rig.owner(rig.body(vector.zero, 0, TICK))
	rig.frames(FRAMES)
	rig.step()

	if #rig.moves == 0 then
		return false, "The body sent no Move to carry View with it"
	elseif #heard ~= 1 or heard[1] ~= math.ceil(KEPT) then
		return false, `After the handshake the server heard {#heard} Views, {heard[1]}, not one of {math.ceil(KEPT)}`
	end

	-- 3) Each call after it is heard rounded up and held to what View carries, and drawn to as given
	for index: number, call: { number } in CALLS do
		handle:setRenderDistance(call[1])
		rig.frames(FRAMES)
		rig.step()

		if #heard ~= index + 1 or heard[index + 1] ~= call[2] then
			return false, `A call of {call[1]} was heard as {heard[index + 1]}, not {call[2]}`
		elseif pool.drawDistance ~= call[1] then
			return false, `After a call of {call[1]} the pool draws to {pool.drawDistance}`
		end
	end

	return true, nil
end
