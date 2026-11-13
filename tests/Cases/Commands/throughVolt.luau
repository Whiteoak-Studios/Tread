--[[
    A Move a client fires through Tread's own Volt scope reaches the
    server's Move listener, and Commands takes it as the listener hands it
    over, so its command runs on its tick and its acknowledgments stand
--]]

--!strict
local Intake = require("../../Fixtures/Commands/Intake")

local START: number = 100 -- The tick stepped when the Move arrives
local STEPS: number = 3 -- Mock frames, enough for a flushed Move to reach the server
local SEED: number = 77 -- A game field the command carries
local ACKNOWLEDGED: number = 4
local RECEIVED: number = 0b1
local DELAY: number = 150 -- Milliseconds

return function (): (boolean, string | nil)
	local rig: Intake.Intake = Intake.new()
	local replicatedStorage: any = rig.globals.game:GetService("ReplicatedStorage")
	local network: any = replicatedStorage.Packages.Tread.Network

	-- The server first, so the player the client joins as is one it hears join
	local server: any = rig.globals.require(network.Server)
	local client: any = rig.globals.require(network.Client)
	local mock: any = rig.globals.require(replicatedStorage.Packages.Volt).mock

	local player: any = mock.players[1]
	local connection: any = rig.Connections.add(player)

	local disconnect: () -> () = server.Move.on(function (from: any, ...: any)
		if from == player then
			rig.Commands.receive(connection, ...)
		end
	end)

	rig.Commands.take(connection, START)

	local command: any = rig:command(START + 1)
	command.jump = true
	command.fields.seed = SEED
	local move: any = rig:encode({ command }, ACKNOWLEDGED, RECEIVED, DELAY)

	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()

	for _ = 1, STEPS do
		mock:step()
	end

	disconnect()

	local ran: any, standIn: boolean = rig.Commands.take(connection, START + 1)
	if standIn then
		return false, "The Move that came through Volt filed no command for its tick"
	elseif ran.number ~= START + 1 or ran.fields.seed ~= SEED or not ran.pressed.jump then
		return false, `The command came through as {ran.number} with seed {ran.fields.seed}, not as it was sent`
	end

	local sequence: number, mask: number = rig.Commands.acknowledged(connection)
	if sequence ~= ACKNOWLEDGED or mask ~= RECEIVED or rig.Commands.delay(connection) ~= DELAY then
		return false, `The Move's acknowledgments came through as {sequence}, {mask}`
	end

	return true, nil
end
