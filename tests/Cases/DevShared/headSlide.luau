--[[
    The dev place slides a body off another's head at 1 stud a second, and
    the hash reads it: with only the collision set alike, the dev table and
    the approved example's still hash apart
--]]

--!strict
local Harness = require("../../Fixtures/DevShared/Harness")

local HEAD_SLIDE: number = 1 -- Studs a second, the dev place's

return function (): (boolean, string | nil)
	local loaded: Harness.Loaded = Harness.load()
	local Config: any = loaded.Config
	local shared: { [string]: any } = loaded.shared
	local example: { [string]: any } = loaded.Example.shared()

	local slide: number = shared.step.headSlide
	if slide ~= HEAD_SLIDE then
		return false, `The dev table slides a body off a head at {slide} studs/s, not {HEAD_SLIDE}`
	elseif example.step.headSlide == slide then
		return false, "The approved example's head slide is the dev place's, so the hash case sets nothing alike"
	end

	local copy: { [string]: any } = table.clone(shared)
	copy.collision = example.collision

	if Config.hash(copy) == Config.hash(example) then
		return false, "The dev table hashed as the example's with its own head slide, so the hash never read it"
	end

	return true, nil
end
