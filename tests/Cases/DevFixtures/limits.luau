--[[
    The fixture hit test refuses a render time past the 500 ms cap as cap
    and one past the history as history, a shot from a hotbar slot with no
    fixture weapon misses as unarmed, and a claim far older than the band is
    flown at the expected time; the fixtures refuse calls before and twice
--]]

--!strict
local DevServer = require("../../Fixtures/DevServer/Harness")
local Rig = require("../../Fixtures/Server/Rig")

local TURN: number = 2 * math.pi
local DELAY: number = 150 -- Milliseconds of interpolation delay the shooter's Move reports, the rewind's least
local REWOUND: number = 5 -- Relay ticks a command's expected render time lies behind it: the 0.1 s round trip and the delay
local SETTLE: number = 30 -- Ticks for both bodies to land and the shooter's eye to settle
local PAST_CAP: number = 11 -- Relay ticks behind the present, one past the 500 ms cap at 20 Hz
local PAST_HISTORY: number = 21 -- One past the 1 s history
local OLD_CLAIM: number = 15 -- Relay ticks behind its command a stale claim lies, far outside the band
local REACH: number = 50 -- Studs the test's segment runs toward the target, past it
local UNARMED: number = 0 -- Empty hands, a slot with no fixture weapon
local AKM: number = 1
local CLOSE: number = 1e-6

-- A shot claiming a render tick, aimed from a point at another with its look packed as the dev table packs it
local function shot(from: any, to: any, renderTick: number, steps: number): { [string]: number }
	local direction: any = (to - from).Unit

	return {
		sequence = 1,
		class = 0,
		renderTick = renderTick,
		fraction = 0,
		yaw = math.round(math.atan2(-direction.X, -direction.Z) / TURN * steps) % steps,
		pitch = math.round(math.asin(direction.Y) / TURN * steps),
	}
end

-- Fires one command's Move from the shooter's client with these game fields, carried across before the next tick
local function send(rig: Rig.Rig, client: any, number: number, fields: { [string]: any })
	local Command: any = rig:require(rig.tread.Codec.Command)
	local Fields: any = rig:require(rig.tread.Codec.Fields)
	local Move: any = rig:require(rig.tread.Codec.Move)

	local command: any = Command.new()
	command.number = number
	command.fields = fields

	local move: any = Move.new()
	local limits: any = { lean = rig.shared.step.lean, headCone = rig.shared.step.headCone }
	Move.encode(move, { command }, 1, 0, 0, DELAY, Fields.compile(rig.shared.fields), limits)
	client.Move.fire(move.command, move.acknowledged, move.received, move.delay, move.commands)
	client.flush()
	rig:deliver()
end

return function (): (boolean, string | nil)
	local dev: DevServer.Loaded = DevServer.load()
	local Shots: any = dev.require(dev.game:GetService("ServerScriptService").Server.Fixtures.Shots)

	local rig: Rig.Rig = Rig.new(function (_: any, settings: any)
		settings.beforeCommand = Shots.queue
	end)

	local server: any = rig:start()

	if pcall(Shots.test, nil, rig:at(0, 0).Position, rig:at(0, 1).Position, 0, 0) then
		return false, "Shots.test ran before Shots.start"
	end

	Shots.start(server, rig.shared, rig.settings)
	if pcall(Shots.start, server, rig.shared, rig.settings) then
		return false, "Shots.start ran a second time"
	end

	local steps: number = rig:require(rig.tread.Constants).ANGLE_STEPS
	local chest: any = rig.shared.hitShapes.Stand.zones.chest

	local client: any = rig:require(rig.tread.Network.Client)
	client.flush()
	rig:deliver()

	local player: any = rig.mock.players[1]
	local shooter: any = server:create(player, rig:at(-20, 25))
	local target: any = server:create(rig.mock:addBot("Target"), rig:at(-20, -5))

	rig:tick(SETTLE)
	rig:deliver()

	-- 1) The test on its own: at the expected time it strikes, and past the cap or the history it refuses
	local eye: any = shooter:getState().eye
	local aim: any = target:getState().root + (chest.from + chest.to) / 2
	local reach: any = eye + (aim - eye).Unit * REACH

	local struck: any = Shots.test(shooter, eye, reach, SETTLE - REWOUND, SETTLE)
	if not struck or struck.target ~= target then
		return false, "The test at the expected render time struck nothing"
	end

	local capped: any, capReason: string? = Shots.test(shooter, eye, reach, SETTLE - PAST_CAP, SETTLE)
	local gone: any, historyReason: string? = Shots.test(shooter, eye, reach, SETTLE - PAST_HISTORY, SETTLE)
	if capped or capReason ~= "cap" then
		return false, `A render time {PAST_CAP} relay ticks back gave {capReason}, not cap`
	elseif gone or historyReason ~= "history" then
		return false, `A render time {PAST_HISTORY} relay ticks back gave {historyReason}, not history`
	end

	-- 2) A shot from empty hands misses on its fire tick, and nothing is struck
	local unarmed: number = SETTLE + 1
	send(rig, client, unarmed, { slot = UNARMED, shots = { shot(eye, aim, unarmed - REWOUND, steps) } })
	rig:tick(1)
	rig:deliver()

	local first: any = Shots.results()[1]
	if not first or first.strike or first.reason ~= "unarmed" or first.tick ~= unarmed then
		return false, "A shot from empty hands did not miss as unarmed on its fire tick"
	end

	-- 3) A claim far older than the band gives way to the expected time, which the cap holds, and still strikes
	local stale: number = unarmed + 1
	local bands: number = #rig:reportedFor("band", player)
	send(rig, client, stale, { slot = AKM, shots = { shot(eye, aim, stale - OLD_CLAIM, steps) } })
	rig:tick(1)

	local second: any = Shots.results()[2]
	if not second or second.inside or math.abs(second.renderTime - (stale - REWOUND)) > CLOSE then
		return false, "A stale claim was not flown at the expected render time with its claim outside the band"
	elseif #rig:reportedFor("band", player) ~= bands + 1 then
		return false, "The stale claim raised no band report"
	elseif not second.strike or second.strike.target ~= target then
		return false, "The stale claim's shot, flown at the expected time, missed a target standing still"
	end

	Shots.clear()
	if #Shots.results() ~= 0 then
		return false, "Shots.clear left resolved shots"
	end

	return true, nil
end
