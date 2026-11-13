--[[
    On a touch screen with no keyboard the live panel shows one button,
    whose tap opens the panel and closes it as the panel's key does, and on
    a device with a keyboard it shows none and the key works as before
--]]

--!strict
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementMethod

local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local LIVE: string = "dev/Client/Live.luau"
local LIVE_RUNS: string = "dev/Shared/LiveRuns.luau"
local PHONE: Handle.Device = { tenFoot = false, touch = true, keyboard = false, display = "Small" }
local DESKTOP: Handle.Device = { tenFoot = false, touch = false, keyboard = true, display = "Large" }
local TOUCH_LAPTOP: Handle.Device = { tenFoot = false, touch = true, keyboard = true, display = "Large" }

type Callback = (...any) -> ()

-- The live panel started on a device, and what the case drives it by
type Panel = {
	Live: any,
	playerGui: any,
	press: (key: any, processed: boolean?) -> (),
	key: EnumItem, -- The panel's
}

-- Each instance's connected callbacks by its signal's name, for the signals Lune's GUI objects lack
local Signals: { [any]: { [string]: { Callback } } } = {}

-- A signal of an instance's by its name, whose connections the case fires itself
local function signal(instance: any, name: string): any
	return {
		Connect = function (_: any, callback: Callback): any
			local named: { [string]: { Callback } } = Signals[instance] or {}
			Signals[instance] = named

			local callbacks: { Callback } = named[name] or {}
			named[name] = callbacks
			table.insert(callbacks, callback)

			return {
				Disconnect = function (_: any)
					local index: number? = table.find(callbacks, callback)
					if index then
						table.remove(callbacks, index)
					end
				end,
			}
		end,
	}
end

-- Lune's GUI objects have no signals, its Player no WaitForChild and its TextService no GetTextSize, so this case
-- answers each. Registered once for the whole run, since Lune refuses a method registered twice
roblox.implementProperty("TextButton", "Activated", function (button: any): any
	return signal(button, "Activated")
end)

roblox.implementProperty("TextBox", "Focused", function (box: any): any
	return signal(box, "Focused")
end)

roblox.implementMethod("TextBox", "GetPropertyChangedSignal", function (box: any, property: string): any
	return signal(box, property)
end)

roblox.implementMethod("Player", "WaitForChild", function (player: any, name: string, _: number?): any
	return player:FindFirstChild(name)
end)

roblox.implementMethod("TextService", "GetTextSize", function (_: any, _: string, size: number, _: any, frame: any): any
	return roblox.Vector2.new(frame.X, size)
end)

--[[
    The live panel started on a device, in a dev client the exploit kit's
    mount sets up, with the run list beside it and the dev scope's report
    and ask standing in
--]]

local function start(device: Handle.Device): Panel
	local rig: Handle.Rig = Handle.new({ device = device, start = false })
	local mounted: Kit.Mounted = Kit.mount(rig)
	local shared: any = rig.globals.game:GetService("ReplicatedStorage").Shared
	local files: { [any]: string } = {}

	local live: any = roblox.Instance.new("ModuleScript")
	live.Name = "Live"
	live.Parent = mounted.config.Parent
	files[live] = LIVE

	local runs: any = roblox.Instance.new("ModuleScript")
	runs.Name = "LiveRuns"
	runs.Parent = shared.Dev
	files[runs] = LIVE_RUNS

	-- The dev scope's client module, with the report the panel hears and the ask its run buttons send
	local results: { [any]: any } = {
		[shared.Network.Client] = {
			runReport = {
				on = function (_: Callback) end,
			},

			run = {
				fire = function (_: string) end,
			},
		},
	}

	local Live: any = Kit.loader(rig.globals.game, files, results, mounted.require)(live)
	Live.start()

	return {
		Live = Live,
		playerGui = rig.player:FindFirstChildOfClass("PlayerGui"),
		press = mounted.press,
		key = mounted.require(mounted.config).live.key,
	}
end

-- The buttons a player sees: each in a ScreenGui that is showing
local function onScreen(playerGui: any): { any }
	local buttons: { any } = {}
	for _, descendant: any in playerGui:GetDescendants() do
		if descendant:IsA("TextButton") and descendant:FindFirstAncestorOfClass("ScreenGui").Enabled then
			table.insert(buttons, descendant)
		end
	end

	return buttons
end

-- A tap on a button, firing what its Activated connects; false when nothing does
local function tap(button: any): boolean
	local named: { [string]: { Callback } }? = Signals[button]
	if not named or not named.Activated then
		return false
	end

	for _, callback: Callback in table.clone(named.Activated) do
		callback()
	end

	return true
end

return function (): (boolean, string | nil)
	-- 1) A touch screen with no keyboard shows one button while the panel is hidden
	local phone: Panel = start(PHONE)
	local buttons: { any } = onScreen(phone.playerGui)
	if #buttons ~= 1 then
		return false, `A touch screen with no keyboard showed {#buttons} buttons with the panel hidden, not 1`
	end

	-- 2) A tap opens the panel with the button still on screen over it, and a second tap closes it
	local button: any = buttons[1]
	if not tap(button) or not phone.Live.open() then
		return false, "A tap on the touch button left the panel hidden"
	elseif not table.find(onScreen(phone.playerGui), button) then
		return false, "The touch button left the screen as the panel opened"
	end

	tap(button)
	if phone.Live.open() then
		return false, "A second tap on the touch button left the panel showing"
	end

	-- 3) The tap and the key toggle the one panel, so the key closes what a tap opened
	tap(button)
	phone.press(phone.key)
	if phone.Live.open() then
		return false, "The panel's key left showing the panel a tap opened"
	end

	-- 4) With a keyboard, touch screen or not, there's no button, and the key opens the panel and closes it
	for _, device: Handle.Device in { DESKTOP, TOUCH_LAPTOP } do
		local keyed: Panel = start(device)
		local shown: number = #onScreen(keyed.playerGui)
		if shown ~= 0 then
			return false, `A keyboard device, touch {device.touch}, showed {shown} buttons with the panel hidden`
		end

		keyed.press(keyed.key)
		if not keyed.Live.open() then
			return false, `The panel's key left it hidden on a keyboard device, touch {device.touch}`
		end

		keyed.press(keyed.key)
		if keyed.Live.open() then
			return false, `A second press of the panel's key left it showing on a keyboard device, touch {device.touch}`
		end
	end

	return true, nil
end
