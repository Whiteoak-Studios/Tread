--[[
    The ESP's cases' rig: the client handle's rig, its handshake matched,
    with a PlayerGui and the dev place's ESP loaded in the same fake game, so
    it hears every message Tread's client hears
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Handle = require("../Client/Handle")
local Kit = require("../Exploits/Kit")

local DRAWN: string = "Esp" -- The Workspace folder and the ScreenGui the ESP draws in
local STEPS: string = "Footsteps" -- The folder inside it its markers sit in

export type Rig = { [string]: any }

local Rig = {}

--[[
    The rig, with the ESP's module loaded and not started, and what a case
    reads back of what it drew
--]]

function Rig.new(): Rig
	local rig: Rig = Handle.new()
	local dataModel: any = rig.globals.game
	local workspace: any = dataModel:GetService("Workspace")

	local playerGui: any = roblox.Instance.new("PlayerGui")
	playerGui.Parent = rig.player

	-- Mounted where the place has it, beside the dev client's Config its values come from
	local mounted: Kit.Mounted = Kit.mount(rig)
	rig.esp = mounted.require(mounted.exploits.Esp)
	rig.workspace = workspace
	rig.playerGui = playerGui

	-- Starts the ESP as the kit does, and gives its switch
	function rig.startEsp(): (on: boolean) -> ()
		return rig.esp.start({ client = rig.handle, shared = rig.shared })
	end

	-- The folder the ESP draws in, nil while it draws nothing
	function rig.drawn(): any
		return workspace:FindFirstChild(DRAWN)
	end

	-- A slot's part, its box and its label, nil while the ESP has drawn none for it
	function rig.slot(slot: number): (any, any, any)
		local drawn: any = rig.drawn()
		if not drawn then
			return nil, nil, nil
		end

		local anchor: any = drawn:FindFirstChild(`{slot}`)
		if not anchor then
			return nil, nil, nil
		end

		local billboard: any = anchor:FindFirstChildOfClass("BillboardGui")

		return anchor, anchor:FindFirstChildOfClass("BoxHandleAdornment"), billboard:FindFirstChildOfClass("TextLabel")
	end

	-- Every footstep marker showing, as its part's position
	function rig.markers(): { any }
		local shown: { any } = {}
		local drawn: any = rig.drawn()
		if not drawn then
			return shown
		end

		for _, anchor: any in drawn[STEPS]:GetChildren() do
			if anchor:FindFirstChildOfClass("SphereHandleAdornment").Visible then
				table.insert(shown, anchor.CFrame.Position)
			end
		end

		return shown
	end

	-- The count's label on screen, nil while it shows none
	function rig.count(): any
		local gui: any = playerGui:FindFirstChild(DRAWN)

		return gui and gui:FindFirstChildOfClass("TextLabel")
	end

	rig.handshake()

	return rig
end

return Rig
