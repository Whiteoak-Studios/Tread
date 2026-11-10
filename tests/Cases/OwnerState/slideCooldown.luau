--[[
    OwnerState carries the crouch slide's cooldown as a u8 at byte 38, after
    the mantle's progress, in Tread's own 42 B: every value round-trips, a
    sliding state with both game blocks empty fills 44 B and decodes
--]]

--!strict
local Environment = require("../../Environment")
local Game = require("../../Fixtures/Codec/Game")

local OWNER_STATE: string = "src/Codec/OwnerState.luau"
local FIELDS: string = "src/Codec/Fields.luau"
local STATE: string = "src/Step/State.luau"
local DECODE: string = "src/Codec/Decode.luau"
local AT: number = 38
local OWN_BYTES: number = 42
local EMPTY_BLOCKS: number = 2 -- The two game blocks' length prefixes, each 0
local VERSION: number = 1

return function (): (boolean, string | nil)
	local OwnerState: any = Environment.load(OWNER_STATE)
	local Fields: any = Environment.load(FIELDS)
	local State: any = Environment.load(STATE)
	local Decode: any = Environment.load(DECODE)
	local empty: any = Fields.compile({ command = {}, rules = {}, server = {}, slot = {}, held = {} })
	local data: buffer = buffer.create(OWN_BYTES + EMPTY_BLOCKS)

	for value: number = 0, 255 do
		local state: { [string]: any } = State.new()
		state.mode = "Slide"
		state.posture = "Crouch"
		state.grounded = true
		state.mantleTicks = 7
		state.mantleRise = 2
		state.slideCooldown = value

		local bytes: number = OwnerState.write(state, data, 0, empty, Game.limits)
		if bytes ~= OWN_BYTES + EMPTY_BLOCKS then
			return false, `A sliding state with empty blocks filled {bytes} B, not {OWN_BYTES + EMPTY_BLOCKS}`
		elseif buffer.readu8(data, AT) ~= value then
			return false, `The cooldown {value} sat at byte {AT} as {buffer.readu8(data, AT)}`
		end

		local into: { [string]: any } = State.new()
		OwnerState.read(data, 0, bytes, into, empty, Game.limits)
		if into.slideCooldown ~= value or into.mode ~= "Slide" then
			return false, `The cooldown {value} read back as {into.slideCooldown}, mode {into.mode}`
		elseif into.mantleTicks ~= 7 or into.mantleRise ~= 2 then
			return false, `The fields beside the cooldown read back as {into.mantleTicks} and {into.mantleRise}`
		end
	end

	-- Tread's decoder gives it by name
	local decoded: any = Decode.decode(VERSION, "owner", data)

	return decoded.slideCooldown == 255 and decoded.mode == "Slide",
		`The decoder gave a cooldown of {decoded.slideCooldown} and the mode {decoded.mode}`
end
