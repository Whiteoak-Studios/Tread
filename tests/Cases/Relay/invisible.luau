--[[
    An Invisible character is hidden from every viewer sent it, teammates
    included, is sent to none while it stays so, makes no footstep entry
    even behind a wall, and is revealed again once it is visible
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/Relay/Harness.luau"
local STRIDE: number = 0.5 -- Studs a tick, the example's walk speed at a 20 Hz relay
local TICKS: number = 40

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local teammate: any = harness:viewer("Teammate")
	local enemy: any = harness:viewer("Enemy")
	local slot: number = harness:spawn("Player", vector.create(10, 0, 0))

	harness:run()
	if teammate.drawn[slot] == nil or enemy.drawn[slot] == nil then
		return false, "Both viewers in range were not revealed the character"
	end

	Harness.Relay.setInvisible(slot, true)
	harness:hide(enemy, slot, true)
	harness:run()

	for _, client: any in { teammate, enemy } do
		if Harness.count(client.seen.hides, slot) ~= 1 then
			return false, `{client.viewer.key.Name} got no hide when the character went Invisible`
		end
	end

	-- It walks within the enemy's earshot behind a wall, and nobody hears or sees it
	for tick: number = 1, TICKS do
		harness.states[slot].position = vector.create(10 + STRIDE * tick, 0, 0)
		harness:run()

		for _, client: any in { teammate, enemy } do
			local seen: any = client.seen
			if #seen.records + #seen.reveals + #seen.footsteps ~= 0 then
				return false, `{client.viewer.key.Name} was sent the Invisible character on tick {tick}`
			end
		end
	end

	Harness.Relay.setInvisible(slot, false)
	harness:run()

	if Harness.count(teammate.seen.reveals, slot) ~= 1 then
		return false, "The teammate was not revealed the character once it was visible again"
	elseif Harness.count(enemy.seen.reveals, slot) ~= 0 then
		return false, "The enemy anti-ESP hides it from was revealed it"
	end

	return true, nil
end
