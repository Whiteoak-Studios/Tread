--[[
    An outlined rig is drawn in one model under one Highlight, made the
    first time and set from spectate.outline to show through walls; every
    outlined rig shares it, a rig leaves it when no longer outlined or when
    released, and a body is never outlined. It refuses no boolean, a slot
    with no rig, and a pool given no spectate settings
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out implementProperty and implementMethod

local Environment = require("../../Environment")

local RIGS: string = "src/Client/Rigs/init.luau"
local RIG: string = "tests/Fixtures/Rigs/Rig.luau"
local STATE: string = "src/Step/State.luau"
local ANIMATE: string = "ReplicatedStorage.Packages.Tread.Client.Rigs.Animate" -- Where the pool requires it
local OUTLINED: string = "TreadOutlined"

local FIRST: number = 1
local SECOND: number = 2
local LATER: number = 3 -- Outlined before it is ever drawn
local NEXT: number = 4
local BODY: number = 10
local NEAR: number = 4 -- Studs from the eye
local FAR: number = 5000 -- Past the draw distance

return function (): (boolean, string | nil)
	-- Lune's RunService has no PreSimulation and its Workspace no BulkMoveTo, which a drawn rig needs. Lune takes one
	-- registration of each a run, so a case that ran first may have made it, as these do; with no collision groups a
	-- ragdoll warns and carries on
	pcall(roblox.implementProperty, "RunService", "PreSimulation", function (_: any): any
		return {
			Connect = function (_: any, _: () -> ()): any
				return { Disconnect = function (_: any) end }
			end,
		}
	end)
	pcall(roblox.implementMethod, "Workspace", "BulkMoveTo", function (_: any, parts: { any }, cframes: { any }, _: any)
		for index: number, part: any in parts do
			part.CFrame = cframes[index]
		end
	end)

	-- Lune loads no animation, so Animate's stand-in plays nothing
	local function nothing(...: any) end
	local Animate: { [string]: any } = {
		check = nothing,
		places = function (_: any, _: any): { any }
			return {}
		end,
		load = function (rig: Model, ...: any): any
			return { rig = rig, tracks = {} }
		end,
		stop = nothing,
		detail = nothing,
		pose = nothing,
		aim = nothing,
		plant = nothing,
		layer = nothing,
		watch = nothing,
		release = nothing,
		markers = function (_: any): { string }
			return {}
		end,
	}

	local Rigs = Environment.load(RIGS, { [ANIMATE] = Animate })
	local Rig = Environment.load(RIG)
	local State = Environment.load(STATE)

	local outline: { [string]: any } = {
		fill = roblox.Color3.fromRGB(255, 60, 60),
		fillTransparency = 0.75,
		outline = roblox.Color3.fromRGB(255, 255, 255),
		outlineTransparency = 0.1,
	}

	local settings: any = Rig.settings({})
	settings.spectate = { outline = outline }
	local rigs = Rigs.new(settings, Rig.drawDistance, Rig.collision())

	local state = State.new()
	state.mode = "Ground"

	local first: any = rigs:checkout(FIRST, {})
	local second: any = rigs:checkout(SECOND, {})
	rigs:pose(FIRST, state, NEAR, 0)
	rigs:pose(SECOND, state, NEAR, 0)
	local folder: any = first.Parent

	-- 1) The first outlined rig moves into a model holding one Highlight, set from the outline
	rigs:outline(FIRST, true)
	local container: any = first.Parent
	local highlight: any = container and container:FindFirstChildOfClass("Highlight")

	if container == folder or container.Name ~= OUTLINED or container.Parent ~= folder then
		return false, "The outlined rig wasn't moved into the outlined model inside the pool's folder"
	elseif not highlight or highlight.Adornee ~= container then
		return false, "The outlined model has no Highlight over it"
	elseif highlight.DepthMode ~= roblox.Enum.HighlightDepthMode.AlwaysOnTop then
		return false, `The Highlight's depth mode is {highlight.DepthMode}, not seen through walls`
	elseif highlight.FillColor ~= outline.fill or highlight.OutlineColor ~= outline.outline then
		return false, "The Highlight's colors aren't the outline's"
	elseif highlight.FillTransparency ~= outline.fillTransparency then
		return false, `The Highlight's fill transparency is {highlight.FillTransparency}`
	elseif math.abs(highlight.OutlineTransparency - outline.outlineTransparency) > 1e-6 then
		return false, `The Highlight's outline transparency is {highlight.OutlineTransparency}`
	end

	-- 2) Every outlined rig shares the one Highlight, and one no longer outlined goes back
	rigs:outline(SECOND, true)
	rigs:outline(SECOND, true)
	local highlights: number = 0
	for _, item: any in folder:GetDescendants() do
		if item:IsA("Highlight") then
			highlights += 1
		end
	end

	if second.Parent ~= container or highlights ~= 1 then
		return false, `Two outlined rigs made {highlights} Highlights, where they share one`
	end

	rigs:outline(FIRST, false)
	if first.Parent ~= folder then
		return false, "A rig no longer outlined stayed in the outlined model"
	end

	-- 3) Past the draw distance an outlined rig leaves Workspace, and comes back outlined
	rigs:pose(SECOND, state, FAR, 0)
	rigs:pose(SECOND, state, NEAR, 0)
	if second.Parent ~= container then
		return false, "An outlined rig drawn again came back outside the outlined model"
	end

	-- 4) A rig outlined before its first pose is drawn outlined, and released it goes back unoutlined
	local later: any = rigs:checkout(LATER, {})
	rigs:outline(LATER, true)
	if later.Parent ~= nil then
		return false, "Outlining a rig drew it before its first pose"
	end

	rigs:pose(LATER, state, NEAR, 0)
	if later.Parent ~= container then
		return false, "A rig outlined before it was drawn wasn't drawn in the outlined model"
	end

	rigs:release(LATER)
	local reused: any = rigs:checkout(NEXT, {})
	rigs:pose(NEXT, state, NEAR, 0)
	if reused ~= later or reused.Parent ~= folder then
		return false, "A released outlined rig came back from the pool still outlined"
	end

	-- 5) A body is never outlined, and an outlined rig that dies leaves the outline
	rigs:ragdoll(SECOND, BODY, nil)
	if second.Parent ~= folder then
		return false, "An outlined rig that died stayed in the outlined model"
	end

	rigs:outline(BODY, true)
	if second.Parent ~= folder then
		return false, "A body was outlined"
	end

	-- 6) What it refuses
	if pcall(rigs.outline, rigs, FIRST, "yes") then
		return false, "Rigs.outline took a string as outlined"
	elseif pcall(rigs.outline, rigs, NEXT + 1, true) then
		return false, "Rigs.outline took a slot with no rig"
	end

	local bare = Rigs.new(Rig.settings({}), Rig.drawDistance, Rig.collision())
	bare:checkout(FIRST, {})
	local took: boolean, failure: any = pcall(bare.outline, bare, FIRST, true)
	if took or not string.find(tostring(failure), "spectate.outline", 1, true) then
		return false, `A pool given no spectate settings outlined a rig, or refused it as "{failure}"`
	end

	bare:destroy()
	rigs:destroy()

	return true, nil
end
