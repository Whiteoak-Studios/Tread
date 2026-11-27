--[[
    Through the server, observe hands a sink a frame every relay tick, with
    the viewer's OwnerState and its character, and each record's reason as
    anti-ESP gave it: Clear in sight, Npc for an NPC, Teammate for a teammate
--]]

--!strict
local Rig = require("../../Fixtures/Server/Rig")

local TICKS: number = 12
local TEAM: number = 2
local CLOSE: number = 0.01 -- Studs, inside OwnerState's 1/512 and a float32's step at the fixture's height
local WRAP: number = 2 ^ 16

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Tread: any = rig:require(rig.tread)

	local viewerBot: any = rig.mock:addBot("Viewer")
	local viewer: any = server:create(viewerBot, rig:at(0, 0))
	local other: any = server:create(rig.mock:addBot("Other"), rig:at(6, 0))
	local mate: any = server:create(rig.mock:addBot("Mate"), rig:at(-6, 0))
	local npc: any = server:createNpc(rig:at(0, 8))
	viewer:setTeam(TEAM)
	mate:setTeam(TEAM)

	local frames: { { tick: number, data: buffer } } = {}
	local lonely: { buffer } = {}
	local stop: () -> () = server:observe(viewerBot, function (tick: number, data: buffer)
		table.insert(frames, { tick = tick, data = data })
	end)

	-- A bot with no character is no viewer, so its frames hold nothing
	local stopLonely: () -> () = server:observe(rig.mock:addBot("Lonely"), function (_: number, data: buffer)
		table.insert(lonely, data)
	end)

	rig:tick(TICKS)

	if #frames ~= TICKS or #lonely ~= TICKS then
		return false, `The sinks heard {#frames} and {#lonely} frames over {TICKS} relay ticks`
	end

	local reasons: { [number]: { [string]: boolean } } = {}
	for index: number, entry: { tick: number, data: buffer } in frames do
		if index > 1 and entry.tick ~= frames[index - 1].tick + 1 then
			return false, `The sink was handed ticks {frames[index - 1].tick} and then {entry.tick}`
		end

		local frame: any = Tread.decode(Tread.CODEC_VERSION, "tap", entry.data)
		if frame.tick ~= entry.tick % WRAP then
			return false, `A frame names tick {frame.tick}, where its sink was handed {entry.tick}`
		elseif not frame.owner or frame.owner.slot ~= viewer._slot or frame.owner.generation ~= viewer._generation then
			return false, `Frame {index} carried no OwnerState for the viewer's character`
		end

		for _, block: any in frame.blocks do
			for _, record: any in block.records do
				reasons[record.slot] = reasons[record.slot] or {}
				reasons[record.slot][record.reason] = true
			end
		end
	end

	local lastOwner: any = Tread.decode(Tread.CODEC_VERSION, "tap", frames[TICKS].data).owner
	local root: Vector3 = viewer:getState().root
	if typeof(lastOwner.position) ~= "Vector3" or (lastOwner.position - root).Magnitude > CLOSE then
		return false, `The last frame's OwnerState puts the viewer at {lastOwner.position}, not {root}`
	end

	local expected: { [number]: string } = { [other._slot] = "Clear", [mate._slot] = "Teammate", [npc._slot] = "Npc" }
	for slot: number, reason: string in expected do
		local given: { [string]: boolean }? = reasons[slot]
		if not given or not given[reason] then
			return false, `Slot {slot}'s records never went with {reason}`
		end

		for heard: string in given do
			if heard ~= reason then
				return false, `Slot {slot}'s records went with {heard} as well as {reason}`
			end
		end
	end

	for index: number, data: buffer in lonely do
		local frame: any = Tread.decode(Tread.CODEC_VERSION, "tap", data)
		if #frame.blocks ~= 0 or frame.owner ~= nil then
			return false, `Frame {index} of a bot with no character carried a block or an OwnerState`
		end
	end

	stop()
	stopLonely()
	rig:tick(1)

	if #frames ~= TICKS or #lonely ~= TICKS then
		return false, "A disconnected sink heard a frame"
	end

	return true, nil
end
