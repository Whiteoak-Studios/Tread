--[[
    The dev server's recorder, on Tread's server, keeps the viewer's
    keyframe first, on the relay tick of the frame after it, then each frame
    in order to the count asked for, and the clip plays on a client
--]]

--!strict
local DevServer = require("../../Fixtures/DevServer/Harness")
local Handle = require("../../Fixtures/Client/Handle")
local PlaybackClip = require("../../Fixtures/Playback/Clip")
local Rig = require("../../Fixtures/Server/Rig")

local FRAMES: number = 10 -- Frames the recording keeps
local BEFORE: number = 4 -- Relay ticks run before it starts, so a keyframe taken outside its sink names an older tick
local AFTER: number = 5 -- Relay ticks run past its fill, which it must not keep
local CLOSE: number = 0.01 -- Studs, inside OwnerState's 1/512 and the eye height's quantum
local WRAP: number = 2 ^ 16

return function (): (boolean, string | nil)
	local rig: Rig.Rig = Rig.new()
	local server: any = rig:start()
	local Tread: any = rig:require(rig.tread)
	local share: number = rig.shared.rates.simulation / rig.shared.rates.relay

	local walkerBot: any = rig.mock:addBot("Walker")
	local walker: any = server:create(walkerBot, rig:at(0, 0))
	server:create(rig.mock:addBot("Watcher"), rig:at(6, 0))
	rig:tick(BEFORE * share)

	local dev: DevServer.Loaded = DevServer.load()
	local Clips: any = dev.require(dev.game:GetService("ServerScriptService").Server.Clips)

	local recording: any = Clips.record(server, walkerBot, FRAMES)
	rig:tick((FRAMES + AFTER) * share)

	local ticks: { buffer } = recording.ticks
	local withheld: { buffer } = recording.withheld
	if #ticks ~= FRAMES + 1 or #withheld ~= FRAMES then
		return false, `The recording kept {#ticks} buffers and {#withheld} withheld, not {FRAMES + 1} and {FRAMES}`
	end

	-- 1) The first buffer is the keyframe, taken on the first frame's own relay tick
	local read: boolean, keyframe: any = pcall(Tread.decode, Tread.CODEC_VERSION, "keyframe", ticks[1])
	if not read then
		return false, `The recording's first buffer is no keyframe: {keyframe}`
	end

	local first: any = Tread.decode(Tread.CODEC_VERSION, "tap", ticks[2])
	if keyframe.tick ~= first.tick then
		return false, `The keyframe names relay tick {keyframe.tick}, where the first frame after it names {first.tick}`
	elseif not keyframe.own or keyframe.own.slot ~= walker._slot then
		return false, "The keyframe's own character is not the walker's"
	end

	-- 2) The frames follow it in order, a relay tick apart, each with the walker's OwnerState
	for index: number = 2, #ticks do
		local frame: any = Tread.decode(Tread.CODEC_VERSION, "tap", ticks[index])
		local wanted: number = (keyframe.tick + index - 2) % WRAP
		if frame.tick ~= wanted then
			return false, `Frame {index - 1} names relay tick {frame.tick}, not {wanted}`
		elseif not frame.owner or frame.owner.slot ~= walker._slot then
			return false, `Frame {index - 1} carries no OwnerState of the walker's`
		end
	end

	-- 3) The withheld frames hold the same ticks, and nothing, since no moderator spectates the walker
	for index: number, data: buffer in withheld do
		local frame: any = Tread.decode(Tread.CODEC_VERSION, "tap", data)
		local wanted: number = (keyframe.tick + index - 1) % WRAP
		if frame.tick ~= wanted or #frame.blocks ~= 0 then
			return false,
				`Withheld frame {index} names tick {frame.tick} with {#frame.blocks} blocks, not {wanted} empty`
		end
	end

	-- 4) Once stopped, it keeps nothing more, and a second stop does nothing
	recording.stop()
	recording.stop()
	rig:tick(AFTER * share)
	if #ticks ~= FRAMES + 1 or #withheld ~= FRAMES then
		return false, "The recording kept frames after it was stopped"
	end

	-- 5) Cut into the server's parts and put back together, the clip plays on a client, whose eye is the walker's
	local devServer: any = dev.game:GetService("ServerScriptService").Server
	local ClipParts: any = dev.require(dev.game:GetService("ReplicatedStorage").Shared.Dev.ClipParts)
	local size: number = dev.require(devServer.Config.Clips).partBytes
	local assembly: any = ClipParts.new()

	for _, isWithheld: boolean in { false, true } do
		local list: { buffer } = isWithheld and withheld or ticks
		local parts: { buffer } = ClipParts.split(list, size)
		for index: number, part: buffer in parts do
			assembly:add(isWithheld, index, #parts, part)
		end
	end

	local took: boolean, clip: any = assembly:take()
	if not took then
		return false, `The recorded clip did not come back from its parts: {clip}`
	end

	-- The log stands in for the pool's watch and outline, as the playback cases have it
	local viewer: Handle.Rig = Handle.new()
	viewer.handshake()
	PlaybackClip.log(viewer)

	local played: boolean, playback: any = pcall(viewer.handle.play, viewer.handle, clip.ticks, clip.withheld)
	if not played then
		return false, `client:play refused the recorded clip: {playback}`
	end

	playback:render(0)
	local eye: Vector3 = viewer.handle:getEye()
	local wanted: Vector3 = walker:getState().eye
	playback:destroy()

	if (eye - wanted).Magnitude > CLOSE then
		return false, `The clip's eye stood at {eye}, where the walker's stood at {wanted}`
	end

	return true, nil
end
