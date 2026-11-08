--[[
    revealAll makes every character a view is sent a pending reveal again,
    with its look and held item, and the view's own look entry too: the
    target's at a spectate's start and switch, the moderator's at its end
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local FIRST_TARGET: vector = vector.zero
local SECOND_TARGET: vector = vector.create(3000, 0, 0)
local MODERATOR: vector = vector.create(-3000, 0, 0)
local BESIDE: vector = vector.create(15, 0, 0)
local OTHER_SIDE: vector = vector.create(0, 0, 25)

-- A body at a place with a look and a held item of its own, and their packed bytes
local function dressed(harness: any, Harness: any, at: vector, head: number): (number, string, string)
	local slot: number = harness:spawn("Player", at)
	local look: { [string]: any } = { head = head }
	local held: { [string]: any } = { item = head }

	Harness.Relay.setLook(slot, look)
	harness.states[slot].held = held

	return slot, harness:pack("slot", look), harness:pack("held", held)
end

-- Why a client's last run didn't reveal a slot with both parts of its look, or nil when it did
local function revealedWhole(Harness: any, client: any, slot: number, look: string, held: string): string?
	local entry: any = Harness.find(client.seen.looks, slot)
	if Harness.count(client.seen.reveals, slot) ~= 1 then
		return `{client.viewer.key.Name} was not revealed slot {slot} again`
	elseif not entry or entry.look ~= look or entry.held ~= held then
		return `{client.viewer.key.Name}'s reveal of slot {slot} came without its look and held item`
	end

	return nil
end

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local first: any = harness:viewer("First")
	local second: any = harness:viewer("Second")
	local moderator: any = harness:viewer("Moderator")
	second.viewer.position = SECOND_TARGET
	moderator.viewer.position = MODERATOR

	local firstOwn: number, firstOwnLook: string, firstOwnHeld: string = dressed(harness, Harness, FIRST_TARGET, 1)
	local near: number, nearLook: string, nearHeld: string = dressed(harness, Harness, BESIDE, 2)
	local across: number, acrossLook: string, acrossHeld: string = dressed(harness, Harness, OTHER_SIDE, 3)
	local far: number, farLook: string, farHeld: string = dressed(harness, Harness, SECOND_TARGET + BESIDE, 4)
	local mine: number, mineLook: string, mineHeld: string = dressed(harness, Harness, MODERATOR + BESIDE, 5)
	local modOwn: number, modOwnLook: string, modOwnHeld: string = dressed(harness, Harness, MODERATOR, 6)
	first.viewer.slot = firstOwn
	moderator.viewer.slot = modOwn
	harness:runs(2)

	-- The start: the first target's view comes again whole, its own look entry included, to it and the moderator
	harness:watch(moderator, first)
	Harness.Relay.revealAll(first.viewer.key)
	harness:run()

	for _, client: any in { first, moderator } do
		local reason: string? = revealedWhole(Harness, client, near, nearLook, nearHeld)
			or revealedWhole(Harness, client, across, acrossLook, acrossHeld)
		if reason then
			return false, `At the start, {reason}`
		end

		local own: any = Harness.find(client.seen.looks, firstOwn)
		if not own or own.look ~= firstOwnLook or own.held ~= firstOwnHeld then
			return false,
				`At the start, {client.viewer.key.Name} got no whole look entry for the target's own character`
		end
	end

	if Harness.count(second.seen.reveals, far) ~= 0 then
		return false, "The start revealed again what another viewer is sent"
	end

	-- The switch: the second target's view comes again, and the first's no longer reaches the moderator
	harness:watch(moderator, second)
	Harness.Relay.revealAll(second.viewer.key)
	harness:run()

	local reason: string? = revealedWhole(Harness, moderator, far, farLook, farHeld)
	if reason then
		return false, `At the switch, {reason}`
	elseif Harness.count(moderator.seen.reveals, near) ~= 0 then
		return false, "After the switch the moderator was still copied the first target's view"
	end

	-- The end: the moderator's own view comes again, with its own look entry
	harness:watch(moderator, nil)
	Harness.Relay.revealAll(moderator.viewer.key)
	harness:run()

	reason = revealedWhole(Harness, moderator, mine, mineLook, mineHeld)
	if reason then
		return false, `At the end, {reason}`
	end

	local own: any = Harness.find(moderator.seen.looks, modOwn)
	if not own or own.look ~= modOwnLook or own.held ~= modOwnHeld then
		return false, "At the end, the moderator got no whole look entry for its own character"
	elseif Harness.count(moderator.seen.reveals, far) ~= 0 then
		return false, "After the end the moderator was still copied the second target's view"
	end

	-- A view nobody has yet is nothing to reveal
	Harness.Relay.revealAll({ Name = "Nobody" })

	return true, nil
end
