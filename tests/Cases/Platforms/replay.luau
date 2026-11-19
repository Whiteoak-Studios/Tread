--[[
    The owner's prediction rides a lift as the server does: a walk onto a
    lift flush with the floor, up with it, and off its far edge raises no
    correction, and a server state off the prediction mid-ride replays
    through the moving lift onto the server's own path, raising no other
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Harness = require("../../Fixtures/Predict/Harness")

local LIFT: number = 11
local SPAWN_TICK: number = 100 -- The harness's spawn tick, which its command 0 runs on
local RISES_FROM: number = 22 -- The command whose tick the lift starts rising on, once the walk is on it
local RISING: number = 12 -- Ticks it rises for
local RISE: number = 0.25 -- Studs a tick
local OFF_AT: number = 28 -- The command the off state is for, while the lift rises with the body on it
local LEAD: number = 2 -- Commands the client runs ahead of each state it is handed, inside the clock's band
local COMMANDS: number = 60 -- Past the walk off the lift's far edge and the landing on the floor
local OFF: vector = vector.create(0.25, 0, 0.5) -- How far the server's state sits from the prediction, still on the lift

-- The lift across the walk's path, 10 studs square, its top flush with the floor until it rises
local function lift(floor: number): { [string]: any }
	local from: number = SPAWN_TICK + RISES_FROM

	return {
		id = LIFT,
		boxes = { { center = roblox.Vector3.new(0, -0.5, 0), size = roblox.Vector3.new(10, 1, 10) } },
		path = function (tick: number, _: number?): any
			local risen: number = math.clamp(tick - from, 0, RISING) * RISE

			return roblox.Vector3.new(-20, floor + risen, 10)
		end,
	}
end

-- A rig whose worlds both hold the lift, spawned and run ahead to the lead
local function rig(): any
	local made: any = Harness.new({ snap = 0, platforms = { lift(1100) } })
	made.spawn()
	made.frames(LEAD)

	return made
end

return function (): (boolean, string | nil)
	-- 1) The server's own states along the whole ride, each handed over as the client runs one command ahead
	local straight: any = rig()
	local rode: boolean = false
	local left: boolean = false

	for command: number = LEAD + 1, COMMANDS do
		straight.frames(1)

		local server: any = straight.twin(command - LEAD)
		straight.Predict.receive(straight.owner(server, LEAD))

		if server.platform == LIFT and server.position.y > 1101 then
			rode = true
		elseif rode and server.platform == 0 then
			left = true
		end

		if #straight.corrections ~= 0 then
			return false, `The server's state for command {command - LEAD} on the ride raised a correction`
		end
	end

	if not rode or not left then
		return false, `The walk rode the lift up {rode} and left it {left}, where it should do both`
	end

	-- 2) A state off the prediction mid-ride replays through the moving lift onto the server's path
	local replayed: any = rig()
	local path: any = nil

	for command: number = LEAD + 1, COMMANDS do
		replayed.frames(1)

		local ran: number = command - LEAD
		if ran < OFF_AT then
			replayed.Predict.receive(replayed.owner(replayed.twin(ran), LEAD))
		elseif ran == OFF_AT then
			path = replayed.twin(ran)
			if path.platform ~= LIFT then
				return false, `The state the server is off on rode {path.platform}, not the lift`
			end

			path.position += OFF
			replayed.Predict.receive(replayed.owner(replayed.copy(path), LEAD))
			if #replayed.corrections ~= 1 then
				return false, `A state off the ride raised {#replayed.corrections} corrections, not 1`
			end
		else
			replayed.step(path, ran, ran)
			replayed.Predict.receive(replayed.owner(replayed.copy(path), LEAD))
			if #replayed.corrections ~= 1 then
				return false, `After the replay the server's state for command {ran} raised another correction`
			end
		end
	end

	return true, nil
end
