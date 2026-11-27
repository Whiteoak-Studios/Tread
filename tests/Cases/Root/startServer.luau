--[[
    Tread.startServer starts the server's handle over Volt.mock: a refused
    table names its key, the handle it gives is the server's, a joining
    client hears the handshake, a bot's character steps onto the floor, and
    a second start is refused
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local MISSING: string = "server.rates.move" -- The one inbound endpoint's rate, which a bad table leaves out
local TICKS: number = 10 -- Long enough to land from the rig's lift
local CLOSE: number = 0.1 -- Studs the character may stand off the floor's top

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local Tread: any = rig:require(rig.tread)
	local Config: any = rig:require(rig.tread.Config)

	local rate: any = rig.settings.rates.move
	rig.settings.rates.move = nil

	local refused: boolean, message: any = pcall(Tread.startServer, rig.shared, rig.settings)
	if refused then
		return false, "Tread.startServer took server settings that give Move no rate"
	elseif not string.find(tostring(message), MISSING, 1, true) then
		return false, `Tread.startServer's refusal of the missing rate named something else: {message}`
	end

	rig.settings.rates.move = rate
	local server: any = Tread.startServer(rig.shared, rig.settings)
	if getmetatable(server) ~= rig.Server then
		return false, "Tread.startServer gave something other than the server's handle"
	end

	-- A client joining Tread's scope hears the shared table's hash, so the endpoints are bound
	local client: any = rig:require(rig.tread.Network.Client)
	local hashes: { number } = {}
	client.Shared.on(function (hash: number, _: number)
		table.insert(hashes, hash)
	end)

	client.flush()
	rig:deliver()

	local bot: any = rig.mock:addBot("Bot")
	local character: any = server:create(bot, rig:at(0, 0))

	-- The server flushes on its relay ticks, so the handshake's answer crosses after them
	rig:tick(TICKS)
	rig:deliver()

	if #hashes ~= 1 or hashes[1] ~= Config.hash(rig.shared) then
		return false, `The joining client heard {#hashes} handshakes, not one with the shared table's hash`
	end

	local state: any = character:getState()
	if not state.grounded or math.abs(state.root.Y - rig.floor) > CLOSE then
		return false, `After {TICKS} ticks the bot's character stands at {state.root}, grounded {state.grounded}`
	end

	if pcall(Tread.startServer, rig.shared, rig.settings) then
		return false, "A second Tread.startServer was taken"
	end

	return true, nil
end
