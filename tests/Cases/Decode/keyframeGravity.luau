--[[
    Tread.decode gives a keyframe's gravity exactly as its f64 carried it,
    68.1, 1e-3 and 1e6 alike, from a keyframe of no characters, platforms
    or own character that is 25 B, and refuses one whose gravity is 0
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Fixtures/Codec/Refuses")

local GLOBALS: string = "tests/Fixtures/Environment/Globals.luau"
local GRAVITY_AT: number = 13 -- After the 12 B header and the platform count, in a keyframe of no characters

return function (): (boolean, string | nil)
	local globals: any = Environment.load(GLOBALS)
	local tread: any = globals.game:GetService("ReplicatedStorage").Packages.Tread
	local Constants: any = globals.require(tread.Constants)
	local Decode: any = globals.require(tread.Codec.Decode)
	local Keyframe: any = globals.require(tread.Codec.Keyframe)
	local version: number = Constants.CODEC_VERSION

	for _, gravity: number in { 68.1, 1e-3, 1e6 } do
		local data: buffer =
			Keyframe.write({ hash = 1, tick = 2, sequence = 3, characters = {}, platforms = {}, gravity = gravity })
		local decoded: any = Decode.decode(version, "keyframe", data)

		if buffer.len(data) ~= 25 then
			return false, `An empty keyframe of gravity {gravity} is {buffer.len(data)} B, not 25`
		elseif decoded.gravity ~= gravity then
			return false, `The keyframe's gravity {gravity} decoded as {decoded.gravity}`
		elseif decoded.own ~= nil or #decoded.characters ~= 0 or #decoded.platforms ~= 0 then
			return false, "An empty keyframe decoded with a character, a platform or an own character"
		end
	end

	local zero: buffer =
		Keyframe.write({ hash = 1, tick = 2, sequence = 3, characters = {}, platforms = {}, gravity = 68.1 })
	buffer.writef64(zero, GRAVITY_AT, 0)

	local refused: boolean, why: string =
		Refuses("gravity is a finite number above 0", Decode.decode, version, "keyframe", zero)
	if not refused then
		return false, `A keyframe of gravity 0 was decoded: {why}`
	end

	return true, nil
end
