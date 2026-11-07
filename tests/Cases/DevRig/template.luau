--[[
    The dev rig stands inside the standing hull with the eye in its head, is
    a template Tread's pool takes, anchored at its root alone and colliding
    with nothing, and gives each state Tread plays a Roblox animation
--]]

--!strict
local Harness = require("../../Fixtures/DevClient/Harness")
local Shared = require("../../Fixtures/DevShared/Harness")

local RIG: string = "dev/Client/Rig.luau"
local CONFIG: string = "dev/Client/Config.luau"
local ROOT: string = "HumanoidRootPart"
local ASSET: string = "^rbxassetid://%d+$" -- An asset id, as each animation's must be
local SLOT: number = 3
local ROUNDING: number = 1e-6 -- Studs a part's edge may pass the hull's by in floating point

-- The states Tread plays an animation for
local STATES: { string } = {
	"idle",
	"walk",
	"sprint",
	"crouchIdle",
	"crouchWalk",
	"jump",
	"fall",
	"land",
	"swimIdle",
	"swim",
	"climb",
	"mantle",
	"downed",
	"crawl",
}

-- How far a part reaches from the origin: its lowest and highest point, and its farthest across
local function extent(part: any): (number, number, number)
	local center: any = part.CFrame.Position
	local half: any = part.Size / 2

	return center.Y - half.Y, center.Y + half.Y, math.max(math.abs(center.X - half.X), math.abs(center.X + half.X))
end

return function (): (boolean, string | nil)
	local step: any = Shared.load().shared.step
	local place: Harness.Game = Harness.new()
	local Rig: any = place.load(RIG)
	local Config: any = place.load(CONFIG)
	local Rigs: any = place.tread("Client.Rigs")
	local collision: any = place.fixture("Rigs.Rig").collision()

	local template: any = Rig.template()
	if template.PrimaryPart == nil or template.PrimaryPart.Name ~= ROOT then
		return false, `The template's PrimaryPart is {template.PrimaryPart}, not its {ROOT}`
	elseif template:FindFirstChildOfClass("Humanoid") then
		return false, "The template holds a Humanoid"
	end

	local controller: any = template:FindFirstChildOfClass("AnimationController")
	if not controller or not controller:FindFirstChildOfClass("Animator") then
		return false, "The template has no AnimationController with an Animator"
	end

	local bottom: number, top: number, across: number = math.huge, -math.huge, 0
	local head: any = template:FindFirstChild("Head")
	for _, item: any in template:GetDescendants() do
		if not item:IsA("BasePart") then
			continue
		end

		if item.Anchored ~= (item.Name == ROOT) then
			return false, `The template's {item.Name} is anchored {item.Anchored}, where only the root is`
		elseif item.CanCollide or item.CanQuery or item.CanTouch then
			return false, `The template's {item.Name} collides, is queried or is touched`
		end

		if item.Name ~= ROOT then
			local low: number, high: number, wide: number = extent(item)
			bottom, top, across = math.min(bottom, low), math.max(top, high), math.max(across, wide)
		end
	end

	local headLow: number, headHigh: number = extent(head)
	if math.abs(bottom) > ROUNDING or top > step.standing + ROUNDING or across > step.radius + ROUNDING then
		return false, `The template spans {bottom} to {top} and {across} across, outside the hull`
	elseif step.eyeStanding < headLow or step.eyeStanding > headHigh then
		return false, `The eye at {step.eyeStanding} sits outside the head, {headLow} to {headHigh}`
	end

	local animations: any = Rig.animations()
	for _, state: string in STATES do
		local animation: any = animations[state]
		if not animation or not animation:IsA("Animation") or not animation.AnimationId:match(ASSET) then
			return false, `The animations give {state} no Animation with an asset id`
		end
	end

	-- Tread's pool takes the template, the joints and the animations, and a rig goes out and back
	local calls: number = 0
	local settings: any = {
		rig = template,
		joints = Rig.joints,
		animations = animations,
		lod = Config.lod,
		bodies = Config.bodies,

		dress = function (rig: any, outfit: any, copy: boolean)
			calls += 1
			Rig.dress(rig, outfit, copy)
		end,

		undress = function (rig: any)
			calls += 1
			Rig.undress(rig)
		end,

		hold = Rig.hold,
	}

	local built: boolean, rigs: any = pcall(Rigs.new, settings, Config.drawDistance.desktop, collision)
	if not built then
		return false, `Tread's rig pool refused the dev template: {rigs}`
	end

	local rig: any = rigs:checkout(SLOT, { head = 1 })
	rigs:hold(SLOT, { item = 2 })
	rigs:release(SLOT)
	if calls ~= 2 or rig:FindFirstChild("Held") then
		return false, `A checkout and release made {calls} look calls and left the hand holding`
	end

	rigs:destroy()

	return true, nil
end
