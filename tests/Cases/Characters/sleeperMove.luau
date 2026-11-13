--[[
    server:createSleeper lays a sleeper wearing its look, refusing a bad
    place or look before any slot is taken; sleeper:moveTo reveals it again
    to its viewers, retests its anti-ESP pairs at once and places its hit
    shapes along the fall from the next relay tick; destroy removes it
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 4
local HEAD: number = 12 -- An item index the example's head slot holds
local HEIGHT: number = 10 -- Studs above the floor the sleeper lies, before it drops
local FAR: number = 20 -- Relay ticks after the move, past the whole fall
local HALF: number = 0.5 -- A share of a relay tick, before the move's first
local CLOSE: number = 0.1 -- Studs a sample may sit from the place it answers for

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local AntiEsp: any = rig:require(rig.tread.Server.AntiEsp)
	local Block: any = rig:require(rig.tread.Codec.Block)
	local Keyframe: any = rig:require(rig.tread.Codec.Keyframe)
	local Slots: any = rig:require(rig.tread.Server.Slots)

	local client: any = rig:require(rig.tread.Network.Client)
	local viewerKey: any = rig.mock.players[1]
	local reveals: { [number]: number } = {}

	client.Relay.on(function (data: buffer)
		local block: any = Block.new()
		Block.read(data, block)

		for index: number = 1, block.revealCount do
			local slot: number = block.reveals[index].slot
			reveals[slot] = (reveals[slot] or 0) + 1
		end
	end)

	client.flush()
	rig:deliver()

	if pcall(server.createSleeper, server, roblox.CFrame.new(0, 0, 1e9), { head = HEAD }) then
		return false, "createSleeper took a place past the play bound"
	elseif pcall(server.createSleeper, server, rig:at(6, 0), { head = -1 }) then
		return false, "createSleeper took a look outside its declaration"
	elseif Slots.count("Sleeper") ~= 0 then
		return false, "A refused createSleeper took a slot"
	end

	server:create(viewerKey, rig:at(0, 0))
	local high: any = roblox.CFrame.new(6, rig.floor + HEIGHT, 0)
	local sleeper: any = server:createSleeper(high, { head = HEAD })
	if not sleeper or Slots.count("Sleeper") ~= 1 then
		return false, "createSleeper made no sleeper"
	end

	rig:tick(TICKS)
	rig:deliver()

	local keyframe: any = Keyframe.read(server:keyframe(viewerKey))
	local seen: any = keyframe.characters[1]
	if not seen or seen.kind ~= "Sleeper" or buffer.len(seen.look) == 0 or not reveals[sleeper._slot] then
		return false, "The viewer was never revealed the sleeper wearing its look"
	end

	-- A tick with nothing changed tests no lying pair, since a visible one holds
	local tests: number = AntiEsp.counts()
	rig:tick(1)
	if AntiEsp.counts() ~= tests then
		return false, "A tick with the sleeper still retested its pair"
	end

	local revealed: number = reveals[sleeper._slot]
	local low: any = rig:at(6, 0)
	sleeper:moveTo(low)
	rig:tick(1)
	rig:deliver()

	if not (AntiEsp.counts() > tests) then
		return false, "The move made none of the sleeper's anti-ESP pairs due"
	elseif reveals[sleeper._slot] <= revealed then
		return false, "The move sent the viewer no fresh reveal of the sleeper"
	end

	-- The move's fall starts at the first relay tick after it was made
	local moved: number = TICKS + 2
	local before: any = server:sampleAt(sleeper, moved - HALF)
	if not before or math.abs(before.position.Y - high.Position.Y) > CLOSE then
		return false, "Before the move's tick the sleeper's shapes were not where it lay"
	end

	local during: any = server:sampleAt(sleeper, moved + HALF)
	local partway: number = during.position.Y
	if not (partway < high.Position.Y and partway > low.Position.Y) then
		return false, `Half a tick into the fall the sleeper lay at {partway}, not between the two places`
	end

	local after: any = server:sampleAt(sleeper, moved + FAR)
	if (after.position - low.Position).Magnitude > CLOSE then
		return false, `Past its fall the sleeper lay at {after.position}, not {low.Position}`
	elseif pcall(sleeper.moveTo, sleeper, "down") then
		return false, "moveTo took a string"
	end

	sleeper:destroy()
	if Slots.count("Sleeper") ~= 0 or #server:getAll() ~= 1 or server:sampleAt(sleeper, moved) ~= nil then
		return false, "The destroyed sleeper kept its slot, its place in getAll or its shapes"
	elseif pcall(sleeper.destroy, sleeper) then
		return false, "A second sleeper:destroy was taken"
	end

	return true, nil
end
