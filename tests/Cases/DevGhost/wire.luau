--[[
    The ghosts' two events cross the dev scope's wire whole: an ask of 16
    slots reaches the server, and a send of 16 ghosts reaches the client
    with every field and its server clock to well inside a microsecond
--]]

--!strict
local Harness = require("../../Fixtures/DevServer/Harness")

local COUNT: number = 16 -- The most slots an ask, and ghosts a send, carries
local STEPS: number = 8 -- Mock steps a message gets to cross, the handshake before the first included
local SLOT_STEP: number = 255 -- Between the asked slots, so they spread across the slot table
local TICK: number = 65535 -- A u16's top
local TIME: number = 1.79e9 + 0.0123 -- A server clock in seconds, as GetServerTimeNow gives one
local TOLERANCE: number = 1e-6
local LABEL: string = "4 relay workers"
local FAR: number = 8000 -- Studs, inside the play bound

-- The ghost of index, each field a value a float32 holds exactly
local function ghostOf(index: number): { [string]: number }
	return {
		slot = index * SLOT_STEP,
		x = index * 0.5,
		y = -index * 0.25,
		z = FAR - index,
		vx = index * 2,
		vy = -index,
		vz = index * 0.125,
	}
end

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local shared: any = loaded.game:GetService("ReplicatedStorage").Shared

	local server: any = loaded.require(shared.Network.Server)
	local client: any = loaded.require(shared.Network.Client)
	local player: any = loaded.mock.players[1]

	local heard: { number }? = nil
	server.ghostAsk.on(function (_: any, slots: { number })
		heard = slots
	end)

	local got: { tick: number, time: number, label: string, ghosts: { any } }? = nil
	client.ghosts.on(function (tick: number, time: number, label: string, ghosts: { any })
		got = { tick = tick, time = time, label = label, ghosts = ghosts }
	end)

	-- 1) An ask of 16 slots reaches the server whole
	local slots: { number } = {}
	for index: number = 1, COUNT do
		table.insert(slots, (index - 1) * SLOT_STEP)
	end

	client.ghostAsk.fire(slots)
	for _ = 1, STEPS do
		if heard then
			break
		end

		loaded.mock:step()
	end

	local asked: { number }? = heard
	if not asked then
		return false, `An ask of {COUNT} slots never reached the server in {STEPS} steps`
	elseif #asked ~= COUNT then
		return false, `An ask of {COUNT} slots reached the server as {#asked}`
	end

	for index: number = 1, COUNT do
		if asked[index] ~= slots[index] then
			return false, `The ask's slot {index} reached the server as {asked[index]}, not {slots[index]}`
		end
	end

	-- 2) A send of 16 ghosts reaches the client whole, its clock to well inside a microsecond
	local ghosts: { { [string]: number } } = {}
	for index: number = 1, COUNT do
		table.insert(ghosts, ghostOf(index))
	end

	server.ghosts.fire(player, TICK, TIME, LABEL, ghosts)
	for _ = 1, STEPS do
		if got then
			break
		end

		loaded.mock:step()
	end

	local arrived: { tick: number, time: number, label: string, ghosts: { any } }? = got
	if not arrived then
		return false, `A send of {COUNT} ghosts never reached the client in {STEPS} steps`
	elseif arrived.tick ~= TICK or arrived.label ~= LABEL then
		return false, `The send reached the client as tick {arrived.tick} labeled {arrived.label}`
	elseif math.abs(arrived.time - TIME) > TOLERANCE then
		return false, `The send's clock {TIME} reached the client as {arrived.time}`
	elseif #arrived.ghosts ~= COUNT then
		return false, `A send of {COUNT} ghosts reached the client as {#arrived.ghosts}`
	end

	for index: number = 1, COUNT do
		local sent: { [string]: number } = ghosts[index]
		local received: any = arrived.ghosts[index]

		for field: string, value: number in sent do
			if received[field] ~= value then
				return false, `Ghost {index}'s {field} reached the client as {received[field]}, not {value}`
			end
		end
	end

	return true, nil
end
