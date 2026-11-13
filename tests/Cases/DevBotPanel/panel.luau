--[[
    The bot panel opens and closes on its key, and on a touch screen with
    no keyboard on its one button, telling the server each time; its spawn
    sends the count and the choices cycled to, a count the event can't
    carry is refused on the panel, and its key drives nothing else
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes and implementProperty

local Harness = require("../../Fixtures/DevClient/Harness")
local Handle = require("../../Fixtures/Client/Handle")
local Kit = require("../../Fixtures/Exploits/Kit")

local BOT_PANEL: string = "dev/Client/BotPanel.luau"
local CONFIG: string = "dev/Client/Config.luau"
local INPUT: string = "dev/Client/Input.luau"
local CLIENT: string = "dev/Client" -- Every file the dev client runs, the kit's tools among them
local MODULE_FILE: string = "%.luau$"
local KEY_CODE: string = "Enum%.KeyCode%.(%w+)" -- A key written into the dev client, by its name
local PHONE: Handle.Device = { tenFoot = false, touch = true, keyboard = false, display = "Small" }
local DESKTOP: Handle.Device = { tenFoot = false, touch = false, keyboard = true, display = "Large" }
local TOUCH_LAPTOP: Handle.Device = { tenFoot = false, touch = true, keyboard = true, display = "Large" }
local COUNT_MOST: number = 2 ^ 16 - 1 -- The most the botSpawn event's u16 count carries
local TYPED: string = "37" -- A count the case types into the box

-- Counts the box holds that the event can't carry, each refused on the panel
local UNCARRIED: { string } = { "many", "0", "2.5", `{COUNT_MOST + 1}` }

type Callback = (...any) -> ()

-- The bot panel started on a device, and what the case drives and reads it by
type Panel = {
	BotPanel: any,
	playerGui: any,
	press: (key: any, processed: boolean?) -> (),
	key: EnumItem, -- The panel's
	radii: { number },
	watched: { boolean }, -- Each botWatch sent, in order
	spawns: { { any } }, -- Each botSpawn sent, its count, behavior and radius
	cleared: () -> number, -- The botClears sent
	heard: { [string]: Callback }, -- The panel's listener for each of the server's events
}

-- Each button's connected callbacks, for the signal Lune's GUI objects lack
local Activated: { [any]: { Callback } } = {}

-- Registered on the class TextButton inherits from, since the live panel's touch case registers TextButton's own
-- after this case runs, and Lune refuses a property registered twice
roblox.implementProperty("GuiButton", "Activated", function (button: any): any
	return {
		Connect = function (_: any, callback: Callback): any
			local callbacks: { Callback } = Activated[button] or {}
			Activated[button] = callbacks
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
end)

--[[
    The bot panel started on a device, in a dev client the exploit kit's
    mount sets up, with the dev scope's events standing in
--]]

local function start(device: Handle.Device): Panel
	local rig: Handle.Rig = Handle.new({ device = device, start = false })
	local mounted: Kit.Mounted = Kit.mount(rig)
	local shared: any = rig.globals.game:GetService("ReplicatedStorage").Shared
	local watched: { boolean } = {}
	local spawns: { { any } } = {}
	local heard: { [string]: Callback } = {}
	local cleared: number = 0

	local module: any = roblox.Instance.new("ModuleScript")
	module.Name = "BotPanel"
	module.Parent = mounted.config.Parent

	local function listen(name: string): any
		return {
			on = function (callback: Callback): () -> ()
				heard[name] = callback

				return function () end
			end,
		}
	end

	-- The dev scope's client module, with the numbers and refusals the panel hears and the asks it sends
	local results: { [any]: any } = {
		[shared.Network.Client] = {
			botStats = listen("botStats"),
			botRefused = listen("botRefused"),

			botSpawn = {
				fire = function (count: number, behavior: string, radius: number?)
					table.insert(spawns, { count, behavior, radius })
				end,
			},

			botClear = {
				fire = function ()
					cleared += 1
				end,
			},

			botWatch = {
				fire = function (shown: boolean)
					table.insert(watched, shown)
				end,
			},
		},
	}

	local BotPanel: any = Kit.loader(rig.globals.game, { [module] = BOT_PANEL }, results, mounted.require)(module)
	BotPanel.start()

	local config: any = mounted.require(mounted.config)

	return {
		BotPanel = BotPanel,
		playerGui = rig.player:FindFirstChildOfClass("PlayerGui"),
		press = mounted.press,
		key = config.botPanel.key,
		radii = config.botPanel.radii,
		watched = watched,
		spawns = spawns,
		heard = heard,

		cleared = function (): number
			return cleared
		end,
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

-- The panel's part of that name
local function part(panel: Panel, name: string): any
	for _, descendant: any in panel.playerGui:GetDescendants() do
		if descendant.Name == name and descendant:FindFirstAncestor("DevBots") then
			return descendant
		end
	end

	error(`The bot panel has no part named {name}`)
end

-- A tap on a button, firing what its Activated connects; false when nothing does
local function tap(button: any): boolean
	local callbacks: { Callback }? = Activated[button]
	if not callbacks or #callbacks == 0 then
		return false
	end

	for _, callback: Callback in table.clone(callbacks) do
		callback()
	end

	return true
end

-- Every Enum.KeyCode name written into the dev client's files under a folder, each once a place it is written
local function keyNames(directory: string, into: { string })
	for _, entry: string in fs.readDir(directory) do
		local path: string = `{directory}/{entry}`
		if fs.isDir(path) then
			keyNames(path, into)
		elseif entry:match(MODULE_FILE) then
			for name: string in fs.readFile(path):gmatch(KEY_CODE) do
				table.insert(into, name)
			end
		end
	end
end

return function (): (boolean, string | nil)
	-- 1) A touch screen with no keyboard shows one button with the panel hidden, whose taps open and close it
	local phone: Panel = start(PHONE)
	local buttons: { any } = onScreen(phone.playerGui)
	if #buttons ~= 1 then
		return false, `A touch screen with no keyboard showed {#buttons} buttons with the panel hidden, not 1`
	end

	local button: any = buttons[1]
	if not tap(button) or not phone.BotPanel.open() then
		return false, "A tap on the touch button left the panel hidden"
	elseif not table.find(onScreen(phone.playerGui), button) then
		return false, "The touch button left the screen as the panel opened"
	end

	-- The tap and the key toggle the one panel, so the key closes what a tap opened
	phone.press(phone.key)
	if phone.BotPanel.open() then
		return false, "The panel's key left showing the panel a tap opened"
	elseif #phone.watched ~= 2 or phone.watched[1] ~= true or phone.watched[2] ~= false then
		return false, `Opening and closing told the server {#phone.watched} times, first {phone.watched[1]}`
	end

	-- 2) With a keyboard, touch screen or not, there's no button, and the key opens the panel and closes it
	for _, device: Handle.Device in { DESKTOP, TOUCH_LAPTOP } do
		local keyed: Panel = start(device)
		local shown: number = #onScreen(keyed.playerGui)
		if shown ~= 0 then
			return false, `A keyboard device, touch {device.touch}, showed {shown} buttons with the panel hidden`
		end

		keyed.press(keyed.key)
		local opened: boolean = keyed.BotPanel.open()
		keyed.press(keyed.key, true) -- Typed into the count's box, so the game took it
		local typed: boolean = keyed.BotPanel.open()
		keyed.press(keyed.key)

		if not opened or not typed or keyed.BotPanel.open() then
			return false, `The panel's key on a keyboard device, touch {device.touch}, opened {opened} then {typed}`
		end
	end

	-- 3) Spawn sends the box's count with the behavior and the area the buttons cycled to
	local desk: Panel = start(DESKTOP)
	desk.press(desk.key)
	local count: any = part(desk, "Count")
	count.Text = TYPED

	tap(part(desk, "Spawn"))
	tap(part(desk, "Behavior"))
	tap(part(desk, "Behavior"))
	for _ = 1, #desk.radii do
		tap(part(desk, "Area"))
	end

	tap(part(desk, "Spawn"))
	tap(part(desk, "Behavior"))
	tap(part(desk, "Area"))
	tap(part(desk, "Spawn"))

	local sent: { string } = {}
	for _, spawn: { any } in desk.spawns do
		table.insert(sent, `{spawn[1]} {spawn[2]} {spawn[3]}`)
	end

	local wanted: string = `{TYPED} Idle {desk.radii[1]} | {TYPED} Sprint nil | {TYPED} Idle {desk.radii[1]}`
	if table.concat(sent, " | ") ~= wanted then
		return false, `The spawns sent were {table.concat(sent, " | ")}, not {wanted}`
	elseif part(desk, "Area").Text ~= `Area: {desk.radii[1]} studs either way of me` then
		return false, `The area button reads {part(desk, "Area").Text} once back at its first radius`
	end

	-- 4) A count the event can't carry is refused on the panel and sends nothing
	for _, typed: string in UNCARRIED do
		count.Text = typed
		tap(part(desk, "Spawn"))

		local refusal: string = `Last refusal: the count {typed} is no whole number from 1 to {COUNT_MOST}`
		if part(desk, "Refusal").Text ~= refusal then
			return false, `The count {typed} left the refusal line at {part(desk, "Refusal").Text}`
		end
	end

	if #desk.spawns ~= 3 then
		return false, `Counts the event can't carry sent {#desk.spawns - 3} spawns`
	end

	-- 5) Clear asks once a tap, and the server's numbers and refusals show as they come
	tap(part(desk, "Clear"))
	desk.heard.botStats(12, "the numbers")
	desk.heard.botRefused("a reason")

	if desk.cleared() ~= 1 then
		return false, `A tap on Clear sent {desk.cleared()} asks`
	elseif
		part(desk, "Status").Text ~= "Panel bots: 12 on the server" or part(desk, "Numbers").Text ~= "the numbers"
	then
		return false, `The numbers showed as {part(desk, "Status").Text} over {part(desk, "Numbers").Text}`
	elseif part(desk, "Refusal").Text ~= "Last refusal: a reason" then
		return false, `The server's refusal showed as {part(desk, "Refusal").Text}`
	end

	-- 6) The panel's key is written into the dev client once, in its own block, and drives none of the dev input
	local place: Harness.Game = Harness.new()
	local key: EnumItem = place.load(CONFIG).botPanel.key
	local names: { string } = {}
	keyNames(CLIENT, names)

	local written: number = 0
	for _, name: string in names do
		if name == key.Name then
			written += 1
		end
	end

	if written ~= 1 then
		return false, `The panel's key {key.Name} is written {written} times into the dev client, not once`
	end

	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")
	local pressed: any = Input.new()
	local rest: any = Input.new()
	pressed:press(key.Name, true)

	local held: any = Command.new()
	local idle: any = Command.new()
	pressed:sample(held)
	rest:sample(idle)

	for field: string, value: any in held do
		if type(value) ~= "table" and value ~= idle[field] then
			return false, `The panel's key {key.Name} drives the dev input's {field}`
		end
	end

	return true, nil
end
