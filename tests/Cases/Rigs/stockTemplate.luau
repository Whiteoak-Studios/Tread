--[[
    A pool takes Roblox's own R15 rig as its template: every rig it checks
    out has none of what the stock rig drives itself with and stands on its
    root alone, while the game's own model keeps all of it
--]]

--!strict
local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STOCK: string = "tests/Fixtures/Rigs/Stock.luau"

local SLOT: number = 2
local OWN: number = 7
local DRESSED: number = 3 -- The dress calls the two checkouts make: a world rig, and the own one with its copy

-- What the pool removes from its clone of the template, by class
local REMOVED: { string } = { "Humanoid", "BaseScript", "BallSocketConstraint", "NoCollisionConstraint" }

-- How many instances of a class a model holds
local function count(model: any, class: string): number
	local found: number = 0
	for _, item: any in model:GetDescendants() do
		if item:IsA(class) then
			found += 1
		end
	end

	return found
end

-- What the pool changes on its clone, as a model holds it: how many of each class, and each part's flags
local function census(model: any): string
	local lines: { string } = { `AnimationController {count(model, "AnimationController")}` }
	for _, class: string in REMOVED do
		table.insert(lines, `{class} {count(model, class)}`)
	end

	for _, item: any in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(lines, `{item.Name} {item.Anchored} {item.CanCollide} {item.CanQuery} {item.CanTouch}`)
		end
	end

	return table.concat(lines, ", ")
end

-- Why a checked-out rig isn't one the pool readied, or nil when it is
local function unready(rig: any): string?
	for _, item: any in rig:GetDescendants() do
		for _, class: string in REMOVED do
			if item:IsA(class) then
				return `A checked-out rig still holds the {item.ClassName} {item:GetFullName()}`
			end
		end

		if item:IsA("BasePart") then
			if item.Anchored ~= (item == rig.PrimaryPart) then
				return `A checked-out rig's {item.Name} is anchored {item.Anchored}, where only its root is`
			elseif item.CanCollide or item.CanQuery or item.CanTouch then
				return `A checked-out rig's {item.Name} still collides, is queried or is touched`
			end
		end
	end

	local controller: any = rig:FindFirstChildOfClass("AnimationController")
	if not controller or not controller:FindFirstChildOfClass("Animator") then
		return "A checked-out rig has no AnimationController with an Animator"
	end

	return nil
end

return function (): (boolean, string | nil)
	local Rigs = Environment.load(RIGS)
	local Rig = Environment.load(RIG)
	local Stock = Environment.load(STOCK)

	local calls: { any } = {}
	local settings: any = Rig.settings(calls)
	local stock: any = Stock.template()
	settings.rig = stock

	-- The fixture holds what a stock rig does, so the checks below have something to find
	for _, class: string in REMOVED do
		if count(stock, class) == 0 then
			return false, `The stock rig fixture holds no {class}`
		end
	end

	local before: string = census(stock)

	local made: boolean, rigs: any = pcall(Rigs.new, settings, Rig.drawDistance, Rig.collision())
	if not made then
		return false, `Rigs.new refused a stock R15 rig: {rigs}`
	end

	-- 1) A world rig, and the own slot's world rig and first-person copy
	rigs:checkout(SLOT, {})
	rigs:checkout(OWN, {}, true)
	if #calls ~= DRESSED then
		return false, `The two checkouts dressed {#calls} rigs, not {DRESSED}`
	end

	for _, call: any in calls do
		local problem: string? = unready(call.rig)
		if problem then
			return false, problem
		end
	end

	-- 2) The game's own model is as it was, through the pool's end too
	rigs:destroy()

	local after: string = census(stock)
	if after ~= before then
		return false, `The game's stock rig changed from {before} to {after}`
	end

	return true, nil
end
