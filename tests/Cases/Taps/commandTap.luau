--[[
    onCommand hears every command a character steps on the tick it runs,
    stand-ins included, a Move's look at its full precision rather than the
    record's, with the state the step produced, past a callback that throws
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local SETTLE: number = 4 -- Ticks before the Move
local PITCH: number = 0.3 -- Radians, which a record's 127 steps to 90° would put 0.003 off
local YAW: number = 1.234
local FULL: number = 1e-4 -- Radians a command's 16-bit look holds a look to
local DELAY: number = 150

-- What one callback call was handed, read during the call, since the command and state are valid only then
type Heard = {
	character: any,
	tick: number,
	number: number,
	pitch: number,
	yaw: number,
	standIn: boolean,
	root: Vector3,
	same: boolean,
}

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local tread: any = rig.tread

	local Command: any = rig:require(tread.Codec.Command)
	local Fields: any = rig:require(tread.Codec.Fields)
	local Move: any = rig:require(tread.Codec.Move)

	local client: any = rig:require(tread.Network.Client)
	local player: any = rig.mock.players[1]
	client.flush()
	rig:deliver()

	local heard: { Heard } = {}
	local stopThrowing: () -> () = server:onCommand(function ()
		error("This command callback throws on purpose, to show the others still hear")
	end)
	local stop: () -> () = server:onCommand(
		function (character: any, tick: number, command: any, isStandIn: boolean, state: any)
			table.insert(heard, {
				character = character,
				tick = tick,
				number = command.number,
				pitch = command.pitch,
				yaw = command.yaw,
				standIn = isStandIn,
				root = state.root,
				same = state == character:getState(),
			})
		end
	)

	if pcall(server.onCommand, server, "callback") then
		return false, "onCommand took a string"
	end

	local bot: any = server:create(rig.mock:addBot("Bot"), rig:at(4, 0))
	local character: any = server:create(player, rig:at(0, 0))
	rig:tick(SETTLE)
	rig:deliver()

	if #heard ~= 2 * SETTLE then
		return false, `onCommand heard {#heard} commands over {SETTLE} ticks of two characters`
	end

	for index: number, entry: Heard in heard do
		if not entry.standIn then
			return false, `Command {index} was not a stand-in, though no Move had come`
		elseif not entry.same then
			return false, `Command {index}'s state was not the table getState gives`
		elseif entry.character ~= bot and entry.character ~= character then
			return false, `Command {index} was handed something other than one of the characters`
		elseif entry.tick ~= (index + 1) // 2 then
			return false, `Command {index} was handed tick {entry.tick}`
		end
	end

	-- A Move for the next tick, its look past what a record holds
	local layout: any = Fields.compile(rig.shared.fields)
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	local command: any = Command.new()
	command.number = SETTLE + 1
	command.pitch = PITCH
	command.yaw = YAW
	command.fields = { slot = 0, shots = {} }

	local move: any = Move.new()
	Move.encode(move, { command }, 1, 0, 0, DELAY, layout, limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()

	local before: number = #heard
	rig:tick(1)

	local stepped: Heard? = nil
	for index: number = before + 1, #heard do
		if heard[index].character == character then
			stepped = heard[index]
		end
	end

	if #heard ~= before + 2 or not stepped then
		return false, "The Move's tick did not hear one command from each character"
	elseif stepped.standIn or stepped.number ~= SETTLE + 1 or stepped.tick ~= SETTLE + 1 then
		return false, `The Move's command was heard as number {stepped.number} on tick {stepped.tick}, or a stand-in`
	elseif math.abs(stepped.pitch - PITCH) > FULL or math.abs(stepped.yaw - YAW) > FULL then
		return false, `The Move's look was heard as {stepped.yaw}, {stepped.pitch}, not at full precision`
	elseif stepped.root ~= character:getState().root then
		return false, "The state heard is not the one the step produced"
	end

	stop()
	stopThrowing()
	stop()
	rig:tick(1)

	if #heard ~= before + 2 then
		return false, "A disconnected command callback still heard"
	end

	return true, nil
end
