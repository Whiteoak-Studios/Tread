--[[
    Two relay runs with no slice between, as a Heartbeat's catch-up ticks
    give, read the viewer's own team afresh after its slot takes a new life,
    so a teammate of its old life is tested as the enemy it now is
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local RED: number = 1

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp

	local own: number, viewer: any = harness:player("Viewer", vector.zero)
	local friend: number = harness:body("Player", vector.create(0, 0, -20))
	local enemy: number = harness:body("Player", vector.create(0, 0, -30))

	AntiEsp.setTeam(own, RED)
	AntiEsp.setTeam(friend, RED)
	harness:slice(0)

	-- The enemy's ask opens the run's round, and the teammate's reads the viewer's team as that run found it
	AntiEsp.isHidden(viewer, enemy)
	if AntiEsp.isHidden(viewer, friend) then
		return false, "A teammate was hidden on the first run's ask"
	end

	-- The viewer's slot takes a new life, with no team, before the next run asks and with no slice since
	harness:reborn(own)

	if not AntiEsp.isHidden(viewer, friend) then
		return false, "The next run's ask kept the viewer's old team, and sent its old teammate untested"
	end

	return true, nil
end
