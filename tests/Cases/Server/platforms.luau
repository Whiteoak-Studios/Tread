--[[
    server:addPlatform puts a platform in the server's step, which a body
    stands on and rides once it is called; server:callPlatform times the
    path from the next tick and tells every joined client, a client joining
    later hears both calls the platform keeps, and the keyframe carries it
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local ID: number = 1
local X: number = -15 -- Where the platform stands, clear of the fixture's parts
local Z: number = 10
local BASE: number = 3 -- Studs above the floor the platform's box center rests before a call
local RISE: number = 0.25 -- Studs it rises a tick once called
local HALF_HEIGHT: number = 0.5 -- Half its box's height, its top above its center
local TICKS: number = 10
local CLOSE: number = 0.1 -- Studs a body may sit from where it should

type Call = { platform: number, tick: number }

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)
	local floor: number = rig.floor

	local platform: any = {
		id = ID,
		boxes = { { center = roblox.Vector3.zero, size = roblox.Vector3.new(8, HALF_HEIGHT * 2, 8) } },

		path = function (tick: number, calledAt: number?): any
			local risen: number = 0
			if calledAt ~= nil then
				risen = (tick - calledAt) * RISE
			end

			return roblox.Vector3.new(X, floor + BASE + risen, Z)
		end,
	}

	local remove: () -> () = server:addPlatform(platform)
	if pcall(server.addPlatform, server, platform) then
		return false, "addPlatform took a second platform with the same id"
	elseif pcall(server.callPlatform, server, ID + 1) then
		return false, "callPlatform took an id no platform holds"
	end

	-- Two calls before the client joins, the second the one the path runs from
	server:callPlatform(ID)
	rig:tick(1)
	server:callPlatform(ID)
	local called: number = 2

	local client: any = rig:require(rig.tread.Network.Client)
	local calls: { Call } = {}
	client.Platform.on(function (id: number, tick: number)
		table.insert(calls, { platform = id, tick = tick })
	end)

	client.flush()
	rig:deliver()
	rig:tick(1)
	rig:deliver()

	if #calls ~= 2 or calls[1].tick ~= 1 or calls[2].tick ~= called then
		return false, `The joining client heard {#calls} calls, not the one before at 1 and the latest at {called}`
	end

	-- A body standing on the platform rides it up from the latest call
	local rider: any = server:create(rig.mock:addBot("Rider"), roblox.CFrame.new(X, floor + BASE + 1, Z))
	rig:tick(TICKS)

	local state: any = rider:getState()
	local tick: number = 2 + TICKS
	local expected: number = floor + BASE + HALF_HEIGHT + (tick - called) * RISE

	if state.platform ~= ID or math.abs(state.root.Y - expected) > CLOSE then
		return false, `The rider stands at {state.root.Y} on platform {state.platform}, not {expected} on {ID}`
	end

	-- Its history holds it in the platform's frame, and sampleAt puts it back in the world
	local sample: any = server:sampleAt(rider, tick, tick)
	if not sample or (sample.position - state.root).Magnitude > CLOSE then
		return false, `sampleAt placed the rider at {sample and sample.position}, not {state.root}`
	end

	local keyframe: any = Keyframe.read(server:keyframe(rig.mock.players[1]))
	local carried: any = keyframe.platforms[1]
	if #keyframe.platforms ~= 1 or carried.id ~= ID or carried.tick ~= called then
		return false, "The keyframe does not carry the platform's latest call"
	end

	-- A call heard live, timed from the next tick
	server:callPlatform(ID)
	rig:tick(1)
	rig:deliver()

	local live: Call? = calls[3]
	if not live or live.tick ~= tick + 1 then
		return false, `The live call reached the client at tick {live and live.tick}, not {tick + 1}`
	end

	-- Removed, the platform leaves the step, and its rider with it
	remove()
	rig:tick(1)
	if rider:getState().platform ~= 0 then
		return false, "The rider still rides a platform that was removed"
	end

	return true, nil
end
