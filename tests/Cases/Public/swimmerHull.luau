--[[
    A standing swimmer takes the crouched hull, so its public hull center
    and standing box sit on the crouched height, while its lying box keeps
    the settings' size and lift
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Environment = require("../../Environment")

local PUBLIC: string = "src/Step/Public.luau"
local SCENE: string = "tests/Fixtures/Step/Scene.luau"

local FEET: vector = vector.create(12, -4.5, -300.25) -- Below the sea's surface at 0
local EYE: vector = vector.create(12, -2, -300.25)
local AHEAD: vector = vector.create(0, 0, -1) -- A level look along -Z

return function (): (boolean, string | nil)
	local Public: any = Environment.load(PUBLIC)
	local Scene: any = Environment.load(SCENE)
	local Vector3: any = roblox.Vector3

	local settings: any = Scene.settings
	local state: any = Scene.state(FEET, false)
	state.mode = "Swim"
	state.posture = "Stand"

	local into: any = Public.new()
	Public.fill(into, state, Scene.world({}), EYE, AHEAD)

	-- Each wanted value is made a Vector3, so it is rounded to the float32 the fill's are
	local width: number = settings.radius + settings.radius
	local box: any = settings.lyingBox
	local center: any = Vector3.new(FEET.x, FEET.y + settings.crouched / 2, FEET.z)
	local hull: any = Vector3.new(width, settings.crouched, width)
	local raised: any = Vector3.new(FEET.x, FEET.y + box.lift, FEET.z)
	local lyingSize: any = Vector3.new(box.width, box.height, box.length)

	local standing: any = into.standingBox
	local lying: any = into.lyingBox
	if into.hullCenter ~= center then
		return false, `A swimmer's hull center was {into.hullCenter}, not the crouched hull's {center}`
	elseif standing.size ~= hull then
		return false, `A swimmer's standing box was sized {standing.size}, not the crouched hull's {hull}`
	elseif standing.cframe.Position ~= center then
		return false, `A swimmer's standing box sat at {standing.cframe.Position}, not on {center}`
	elseif lying.size ~= lyingSize then
		return false, `A swimmer's lying box was sized {lying.size}, not the settings' {lyingSize}`
	elseif lying.cframe.Position ~= raised then
		return false, `A swimmer's lying box sat at {lying.cframe.Position}, not {raised}`
	end

	return true, nil
end
