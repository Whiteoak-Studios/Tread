--[[
    Tread's scope sends only when its side flushes: a Move, the handshake
    before it and a relay block each wait until flush is called, and then
    reach the other side's listener with every value they were fired with
--]]

--!strict
local Environment = require("../../Environment")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local STEPS: number = 3 -- Heartbeats, each of which would send at Volt's default cadence of one
local BLOCK: string = "relay block"
local FIELDS: string = "game fields"

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local replicatedStorage: any = globals.game:GetService("ReplicatedStorage")
	local network: any = replicatedStorage.Packages.Tread.Network

	-- The server first, so the player the client joins as is one it hears join
	local server: any = globals.require(network.Server)
	local client: any = globals.require(network.Client)
	local mock: any = globals.require(replicatedStorage.Packages.Volt).mock

	local function step()
		for _ = 1, STEPS do
			mock:step()
		end
	end

	local moves: { { any } } = {}
	server.Move.on(function (...: any)
		table.insert(moves, { ... })
	end)

	local blocks: { string } = {}
	client.Relay.on(function (block: buffer)
		table.insert(blocks, buffer.tostring(block))
	end)

	local sent: { [string]: any } = {
		moveX = 127,
		moveZ = -127,
		buttons = 65535,
		yaw = 40000,
		pitch = -16384,
		lean = 3,
		headYaw = -4,
		headPitch = 9,
		fields = buffer.fromstring(FIELDS),
	}

	client.Move.fire(7, 6, 1, 100, { sent })
	step()

	if #moves ~= 0 then
		return false, "A Move reached the server before the client flushed"
	end

	client.flush()
	step()

	if #moves ~= 1 then
		return false, `{#moves} Moves reached the server once the client flushed, where it sent 1`
	end

	local player: any, command: any, acknowledged: any, received: any, delay: any, commands: any =
		table.unpack(moves[1])
	if player ~= mock.players[1] or command ~= 7 or acknowledged ~= 6 or received ~= 1 or delay ~= 100 then
		return false, `The Move arrived as {player}, {command}, {acknowledged}, {received}, {delay}, not as it was sent`
	end

	local arrived: { [string]: any } = commands[1]
	for field: string, value: any in sent do
		local same: boolean = arrived[field] == value
		if field == "fields" then
			same = buffer.tostring(arrived.fields) == FIELDS
		end

		if not same then
			return false, `The Move's command arrived with {field} {arrived[field]}, where it was sent with {value}`
		end
	end

	server.Relay.fire(mock.players[1], buffer.fromstring(BLOCK))
	step()

	if #blocks ~= 0 then
		return false, "A relay block reached the client before the server flushed"
	end

	server.flush()
	step()

	if #blocks ~= 1 or blocks[1] ~= BLOCK then
		return false, `The client heard {#blocks} relay blocks once the server flushed, where it sent 1`
	end

	return true, nil
end
