--[[
    AntiEsp.passed passes over a teammate, an NPC, a free slot and the
    viewer's own slot: handed only those, it opens no round, so no pair is
    dropped, and a teammate's pair stays unstamped, as an ask leaves it;
    a teammate's sleeper, which an ask tests, it keeps
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local CONSTANTS: string = "src/Constants.luau"
local REACH: number = 4 -- Studs across the ground from a body's feet that every ray to it ends within
local TEAM: number = 1
local DUE: number = 0.5 -- When every pair seen at 0 s is rechecked, at the example's 2 Hz
local LATER: number = 1
local SLEEPER_SEEN: number = 1.1 -- When the teammate's sleeper is first tested
local SLEEPER_MOVED: number = 1.2 -- When its move makes it due again, after a run that left its viewer out
local OWN_RUN: number = 1.5 -- When the other viewer's enemy pair is rechecked, after a run of passed of its own slot

return function (): (boolean, string | nil)
	local Constants: any = Environment.load(CONSTANTS)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new(nil, Harness.clock().read)
	local AntiEsp: any = Harness.AntiEsp
	AntiEsp.useWhole(true)

	local own: number, left: any = harness:player("Left", vector.zero)
	local otherOwn: number, other: any = harness:player("Other", vector.create(0, 0, 50)) -- On no team
	local enemy: number = harness:body("Player", vector.create(20, 0, 0))
	local mate: number = harness:body("Player", vector.create(-20, 0, 0))
	local npc: number = harness:body("Npc", vector.create(0, 0, -20))
	local joining: number = harness:body("Player", vector.create(30, 0, 30)) -- An enemy until it joins the team
	local sleeping: number = harness:body("Sleeper", vector.create(-30, 0, 30)) -- A teammate's sleeper
	local free: number = Constants.SLOTS - 1 -- A slot no body takes

	AntiEsp.setTeam(own, TEAM)
	AntiEsp.setTeam(mate, TEAM)
	AntiEsp.setTeam(sleeping, TEAM)

	-- How many of a slice's rays a viewer cast at a body
	local function raysAt(viewer: any, slot: number): number
		local feet: vector = harness.states[slot].position
		local count: number = 0

		for _, ray: any in harness.rays do
			local offset: vector = ray.to - feet
			if ray.origin.z == viewer.position.z and math.sqrt(offset.x * offset.x + offset.z * offset.z) < REACH then
				count += 1
			end
		end

		return count
	end

	-- Every pair seen at 0 s, the teammate never tested
	AntiEsp.isHidden(left, enemy)
	AntiEsp.isHidden(left, mate)
	AntiEsp.isHidden(left, joining)
	AntiEsp.isHidden(other, enemy)
	harness:slice(0)

	-- A run of nothing but passed of a teammate, an NPC and a free slot: no round, so every pair stays asked
	AntiEsp.passed(left, { mate, npc, free }, 3)
	harness:slice(DUE)

	if raysAt(left, enemy) == 0 or raysAt(other, enemy) == 0 or raysAt(left, joining) == 0 then
		return false, "passed of only a teammate, an NPC and a free slot opened a round that dropped the run's pairs"
	end

	-- The enemy joins the team, and the next run asks for the other viewer and hands passed both of the left one's
	AntiEsp.setTeam(joining, TEAM)
	AntiEsp.isHidden(other, enemy)
	AntiEsp.passed(left, { enemy, joining }, 2)
	harness:slice(LATER)

	if raysAt(left, enemy) == 0 then
		return false, "The left viewer's enemy pair, handed to passed, wasn't kept"
	elseif raysAt(left, joining) ~= 0 then
		return false,
			`passed kept the pair of a target that joined the viewer's team, which cast {raysAt(left, joining)}`
	end

	-- Its next asks: the kept enemy pair as tested, the new teammate never hidden
	if AntiEsp.isHidden(left, enemy) or AntiEsp.reason(left.key, enemy) ~= "Clear" then
		return false, `The kept enemy pair's next ask found {AntiEsp.reason(left.key, enemy)}`
	elseif AntiEsp.isHidden(left, joining) or AntiEsp.reason(left.key, joining) ~= "Teammate" then
		return false, `The new teammate's next ask found {AntiEsp.reason(left.key, joining)}`
	end

	-- The same run asks about a teammate's sleeper, which an ask tests as any sleeper, and the next run leaves the
	-- viewer out, handing it to passed, which keeps it, so its move makes it due and it is retested
	AntiEsp.isHidden(left, sleeping)
	AntiEsp.isHidden(other, enemy)
	harness:slice(SLEEPER_SEEN)

	if raysAt(left, sleeping) == 0 then
		return false, "The ask of a teammate's sleeper made no pair to test"
	end

	AntiEsp.isHidden(other, enemy)
	AntiEsp.passed(left, { sleeping }, 1)
	AntiEsp.moved(sleeping)
	harness:slice(SLEEPER_MOVED)

	if raysAt(left, sleeping) == 0 then
		return false, "passed passed over a teammate's sleeper, which an ask would have kept"
	end

	-- A run of nothing but passed of the other viewer's own slot, on no team: no round, so its enemy pair stays asked
	AntiEsp.passed(other, { otherOwn }, 1)
	harness:slice(OWN_RUN)

	if raysAt(other, enemy) == 0 then
		return false, "passed of only the viewer's own slot opened a round that dropped its pair"
	end

	return true, nil
end
