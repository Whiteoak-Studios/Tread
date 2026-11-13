--[[
    A player carrying the viewer's team is never hidden or tested, behind
    walls or not, while one on another team or none is; a team lasts only
    the life it was given for, nil takes it away, and a sleeper on the
    viewer's team is still tested
--]]

--!strict
local Environment = require("../../Environment")

local HARNESS: string = "tests/Fixtures/AntiEsp/Harness.luau"
local RED: number = 1
local BLUE: number = 2

return function (): (boolean, string | nil)
	local Harness: any = Environment.load(HARNESS)
	local harness: any = Harness.new()
	local AntiEsp: any = Harness.AntiEsp
	harness.wall = Harness.solid

	local slot: number, viewer: any = harness:player("Viewer", vector.zero)
	local friend: number = harness:body("Player", vector.create(0, 0, -20))
	local enemy: number = harness:body("Player", vector.create(0, 0, -30))
	local loner: number = harness:body("Player", vector.create(0, 0, -40))
	local sleeper: number = harness:body("Sleeper", vector.create(0, 0, -50))

	AntiEsp.setTeam(slot, RED)
	AntiEsp.setTeam(friend, RED)
	AntiEsp.setTeam(enemy, BLUE)
	AntiEsp.setTeam(sleeper, RED)

	for _, target: number in { friend, enemy, loner, sleeper } do
		AntiEsp.isHidden(viewer, target)
	end

	harness:slice(0)

	if AntiEsp.isHidden(viewer, friend) then
		return false, "A teammate behind walls was hidden"
	elseif harness:endingAt(vector.create(0, harness.server.antiEsp.aim.Stand[1].up, -20)) ~= 0 then
		return false, "A teammate was ray-tested"
	elseif not AntiEsp.isHidden(viewer, enemy) or not AntiEsp.isHidden(viewer, loner) then
		return false, "An enemy on another team or none was not hidden behind walls"
	elseif not AntiEsp.isHidden(viewer, sleeper) then
		return false, "A sleeper on the viewer's team was not tested like any other"
	end

	-- A new life of the teammate's slot starts with no team, so it is an enemy until it is given one
	harness:reborn(friend)
	if not AntiEsp.isHidden(viewer, friend) then
		return false, "The teammate's slot kept its team into a new life"
	end

	AntiEsp.setTeam(friend, RED)
	AntiEsp.setTeam(enemy, RED)
	if AntiEsp.isHidden(viewer, friend) or AntiEsp.isHidden(viewer, enemy) then
		return false, "A player given the viewer's team was still hidden"
	end

	-- With no team of its own the viewer has no teammates
	AntiEsp.setTeam(slot, nil)
	if not AntiEsp.isHidden(viewer, friend) then
		return false, "The viewer whose team was taken away still had a teammate"
	end

	return true, nil
end
