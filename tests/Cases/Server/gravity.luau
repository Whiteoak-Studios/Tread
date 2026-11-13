--[[
    server:setGravity refuses what is no finite number above 0, changing
    and sending nothing; a call after tick n reaches joined clients as n + 1,
    sets Workspace.Gravity, steps bodies under it from n + 1, follows the
    handshake for a later joiner and rides the keyframe
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")
local Rig = require("../../Fixtures/Server/Rig")

local Volt = require("@volt")

local CLIENT: string = "src/Network/Client.luau"
local VOLT: string = "ReplicatedStorage.Packages.Volt"
local REFUSED: string = "server:setGravity"
local CHANGED: number = 30 -- Studs/s², the gravity the call sets
local X: number = -15 -- Where the faller drops, clear of the fixture's parts
local Z: number = 10
local HEIGHT: number = 20 -- Studs over the floor it is built at, 1,020 up, inside the 1,024-stud height bound
local AIRBORNE: number = 4 -- Ticks it falls before the call
local AFTER: number = 9 -- Ticks it falls after
local FEWEST: number = 2 -- The fewest airborne tick pairs each gravity must be checked on
local TOLERANCE: number = 1 / 64 -- Studs/s a tick's change in vertical speed may sit off its gravity's
local CLOSE: number = 1e-6

-- What a client heard, in order: the handshake's tick, or a gravity and its tick
type Heard = { name: string, gravity: number?, tick: number }

-- One tick of the faller's step, as the command tap gave it
type Fall = { velocity: number, mode: string }

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)
	local Tick: any = rig:require(rig.tread.Server.Tick)
	local workspace: any = rig.globals.game:GetService("Workspace")
	local shared: number = rig.shared.step.gravity
	local rate: number = rig.rate

	-- A player whose client side joins on its own transport, and what that side hears
	local function join(name: string): (any, { Heard })
		local player: any, transport: any = rig.mock:join(name)
		local network: any = Environment.load(CLIENT, {
			[VOLT] = {
				start = function (schema: any): any
					return Volt.start(schema, transport)
				end,
			},
		})

		local heard: { Heard } = {}
		network.Shared.on(function (_: number, tick: number)
			table.insert(heard, { name = "Shared", gravity = nil, tick = tick })
		end)
		network.Gravity.on(function (gravity: number, tick: number)
			table.insert(heard, { name = "Gravity", gravity = gravity, tick = tick })
		end)

		network.flush()
		rig:deliver()
		rig:tick(1)
		rig:deliver()

		return player, heard
	end

	-- Whether a client heard any gravity
	local function heardGravity(heard: { Heard }): boolean
		for _, message: Heard in heard do
			if message.name == "Gravity" then
				return true
			end
		end

		return false
	end

	-- 1) A client joined with no call hears the handshake and no gravity
	local early: any, earlyHeard: { Heard } = join("Early")
	if #earlyHeard ~= 1 or earlyHeard[1].name ~= "Shared" then
		return false, `A client joined with no call heard {#earlyHeard} messages, not the handshake alone`
	end

	-- 2) The refusals change nothing and send nothing
	local before: number = workspace.Gravity
	for _, gravity: any in { 0, -CHANGED, math.huge, 0 / 0, "30" } do
		local refused: boolean, why: string = Refuses(REFUSED, server.setGravity, server, gravity)
		if not refused then
			return false, `server:setGravity({gravity}) wasn't refused: {why}`
		end
	end

	local bare: boolean, why: string = Refuses(REFUSED, server.setGravity, server)
	if not bare then
		return false, `server:setGravity() wasn't refused: {why}`
	end

	rig:tick(1)
	rig:deliver()
	if heardGravity(earlyHeard) then
		return false, "A refused call sent the client a gravity"
	elseif workspace.Gravity ~= before then
		return false, `A refused call set Workspace.Gravity to {workspace.Gravity}`
	elseif Keyframe.read(server:keyframe(early)).gravity ~= shared then
		return false, `The keyframe carried {Keyframe.read(server:keyframe(early)).gravity} before any call`
	end

	-- 3) A body falling across the call
	local faller: any = server:create(rig.mock:addBot("Faller"), roblox.CFrame.new(X, rig.floor + HEIGHT, Z))
	local falls: { [number]: Fall } = {}
	local stop: () -> () = server:onCommand(function (character: any, tick: number, _: any, _: boolean, state: any)
		if character == faller then
			falls[tick] = { velocity = state.velocity.Y, mode = state.mode }
		end
	end)

	rig:tick(AIRBORNE)
	local n: number = Tick.counts()
	server:setGravity(CHANGED)

	if math.abs(workspace.Gravity - CHANGED) > CLOSE then
		return false, `Workspace.Gravity reads {workspace.Gravity} after the call, not {CHANGED}`
	end

	rig:tick(1)
	rig:deliver()

	local live: Heard? = earlyHeard[#earlyHeard]
	if not live or live.name ~= "Gravity" or live.gravity ~= CHANGED or live.tick ~= n + 1 then
		return false, `The joined client heard {live and live.name} {live and live.gravity} at {live and live.tick}`
	end

	rig:tick(AFTER - 1)
	stop()

	-- Each airborne tick's change in vertical speed is its own tick's gravity's, 68.1 to n and the call's from n + 1
	local under: number, over: number = 0, 0
	for tick: number = n - AIRBORNE + 2, n + AFTER do
		local now: Fall?, last: Fall? = falls[tick], falls[tick - 1]
		if not now or not last then
			return false, `The faller wasn't stepped on tick {tick - 1} or {tick}`
		elseif now.mode ~= "Air" then
			return false, `The faller was in {now.mode} on tick {tick}, before the case could check its fall`
		end

		if last.mode == "Air" then
			local gravity: number = shared
			if tick > n then
				gravity = CHANGED
				over += 1
			else
				under += 1
			end

			local change: number = now.velocity - last.velocity
			if math.abs(change + gravity / rate) > TOLERANCE then
				return false, `On tick {tick} the faller's vertical speed changed {change}, not {-gravity / rate}`
			end
		end
	end

	if under < FEWEST or over < FEWEST then
		return false, `The fall was checked on {under} ticks under {shared} and {over} under {CHANGED}`
	end

	-- 4) A later joiner hears the handshake, then the gravity with the tick it applies from
	local _, lateHeard: { Heard } = join("Late")
	local first: Heard?, second: Heard? = lateHeard[1], lateHeard[2]
	if #lateHeard ~= 2 or not first or not second or first.name ~= "Shared" or second.name ~= "Gravity" then
		return false, `The later joiner heard {#lateHeard} messages, not the handshake and then the gravity`
	elseif second.gravity ~= CHANGED or second.tick ~= n + 1 then
		return false, `The later joiner heard gravity {second.gravity} from {second.tick}, not {CHANGED} from {n + 1}`
	end

	-- 5) The keyframe carries the gravity in force
	local keyed: number = Keyframe.read(server:keyframe(early)).gravity
	if keyed ~= CHANGED then
		return false, `The keyframe carried gravity {keyed}, not {CHANGED}`
	end

	faller:destroy()

	return true, nil
end
