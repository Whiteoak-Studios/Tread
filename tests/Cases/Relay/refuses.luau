--[[
    The relay refuses what it can't take: running or dressing before it
    starts, starting twice or without its functions, a value that is no
    slot, an Invisible switch that is no boolean, a look its declarations
    don't hold, and a viewer whose own slot is no slot
--]]

--!strict
local Environment = require("../../Environment")

local RELAY: string = "src/Server/Relay.luau"
local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local NOT_SLOTS: { number } = { -1, 4096, 1.5 }

-- Why a call did not error, or nil when it did
local function refused(call: (...any) -> ...any, ...: any): string?
	local passed: boolean = pcall(call, ...)
	if passed then
		return "it was taken"
	end

	return nil
end

return function (): (boolean, string | nil)
	local Relay: any = Environment.load(RELAY)

	if refused(Relay.run, 1, {}, {}, {}) then
		return false, "Relay.run ran before Relay.start"
	elseif refused(Relay.setLook, 0, {}) then
		return false, "Relay.setLook ran before Relay.start"
	elseif refused(Relay.start, {}, nil, function () end, function () end) then
		return false, "Relay.start took a send that is no function"
	end

	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	Relay = Harness.Relay

	if refused(Relay.start, {}, function () end, function () end, function () end) then
		return false, "Relay.start ran a second time"
	end

	for _, slot: number in NOT_SLOTS do
		for _, member: string in { "reveal", "isSent", "viewersOf" } do
			if refused(Relay[member], slot) then
				return false, `Relay.{member} took {slot} as a slot`
			end
		end

		if refused(Relay.setLook, slot, {}) or refused(Relay.setInvisible, slot, true) then
			return false, `Relay.setLook or setInvisible took {slot} as a slot`
		elseif refused(Relay.shotNear, {}, slot) then
			return false, `Relay.shotNear took {slot} as a slot`
		end
	end

	local slot: number = harness:spawn("Player", vector.zero)
	if refused(Relay.setInvisible, slot, "yes") then
		return false, "Relay.setInvisible took a string for its switch"
	elseif refused(Relay.setLook, slot, "a look") then
		return false, "Relay.setLook took a string for its fields"
	elseif refused(Relay.setLook, slot, { head = 2 ^ 16 }) then
		return false, "Relay.setLook took a look field its 16 bits can't hold"
	end

	local client: any = harness:viewer("Viewer")
	client.viewer.slot = NOT_SLOTS[2]
	if refused(harness.run, harness) then
		return false, "A viewer whose own slot is no slot was taken"
	end

	return true, nil
end
