--[[
    The ghosts ask for the 16 drawn players nearest the camera but the own,
    again only on a change and at most every 0.25 s, box what the newest
    message names, restart means on a new label, and switch on G or a button
--]]

--!strict
local fs = require("@lune/fs")
local roblox: any = require("@lune/roblox") -- Its typedefs leave out the datatypes

local Client = require("../../Fixtures/DevGhost/Client")
local Harness = require("../../Fixtures/DevClient/Harness")

local INPUT: string = "dev/Client/Input.luau"
local CLIENT: string = "dev/Client" -- Every file the dev client runs, the kit's tools among them
local MODULE_FILE: string = "%.luau$"
local KEY_CODE: string = "Enum%.KeyCode%.(%w+)" -- A key written into the dev client, by its name
local START: number = 1790000000 -- The server's clock as the ghosts go on, seconds
local CLOSE: number = 1e-6 -- Studs and seconds, past a float's rounding of the sums below
local PLACED_CLOSE: number = 1e-5 -- Studs, past Lune's rounding of a CFrame and a size, 2.78 read back as 2.7799988
local MILLISECONDS: number = 1000
local OWN: number = 0 -- The local player's slot
local BOTS: number = 17 -- Players drawn besides the local one, one past an ask's 16
local SPACING: number = 10 -- Studs between them along the camera's look
local NPC: number = 30 -- A drawn NPC, nearer than every player
local UNPOSED: number = 31 -- A player drawn with no pose shown yet
local RIDER: number = 32 -- A player drawn on a platform
local UNDRAWN: number = 40 -- A slot the interpolation poses that no rig is drawn for
local SPRINT: number = 18 -- Studs a second
local LEAD: number = 0.0625 -- Seconds a message's stamp stands before the frame it reaches
local DELAY: number = 0.05 -- Seconds of interpolation delay while the means are read
local LABEL: string = "4 relay workers"
local NEXT_LABEL: string = "3 relay workers"
local EYE_HEIGHT: number = 2.5 -- Studs the camera stands above the floor, looking along -Z
local PHONE: Client.Device = { touch = true, keyboard = false }
local DESKTOP: Client.Device = { touch = false, keyboard = true }
local TOUCH_LAPTOP: Client.Device = { touch = true, keyboard = true }

-- A bot's feet, along the camera's look
local function along(index: number): vector
	return vector.create(0, 0, -SPACING * index)
end

-- A ghost as the ghosts event carries it
local function ghost(slot: number, feet: vector, velocity: vector): { [string]: number }
	return { slot = slot, x = feet.x, y = feet.y, z = feet.z, vx = velocity.x, vy = velocity.y, vz = velocity.z }
end

-- The slots an ask names, joined, and whether one is named twice
local function listed(slots: { number }): (string, boolean)
	local seen: { [number]: boolean } = {}
	local twice: boolean = false
	for _, slot: number in slots do
		twice = twice or seen[slot] == true
		seen[slot] = true
	end

	return table.concat(slots, ","), twice
end

-- The slots 1 to the last given, leaving out the one given
local function bots(last: number, without: number?): string
	local slots: { number } = {}
	for slot: number = 1, last do
		if slot ~= without then
			table.insert(slots, slot)
		end
	end

	return table.concat(slots, ",")
end

-- The ghost drawn for a slot, its anchor and box, nil while there is none
local function box(rig: Client.Rig, slot: number): (any, any)
	local drawn: any = rig.workspace:FindFirstChild(rig.config.drawn)
	local anchor: any = drawn and drawn:FindFirstChild(`{slot}`)

	return anchor, anchor and anchor:FindFirstChildOfClass("BoxHandleAdornment")
end

-- Whether a box stands at a center with a size, each within PLACED_CLOSE
local function placed(anchor: any, adornment: any, center: vector, size: vector): boolean
	local at: any = anchor.CFrame.Position
	local made: any = adornment.Size
	local moved: vector = vector.create(at.X, at.Y, at.Z) - center
	local sized: vector = vector.create(made.X, made.Y, made.Z) - size

	return vector.magnitude(moved) < PLACED_CLOSE and vector.magnitude(sized) < PLACED_CLOSE
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
	local rig: Client.Rig = Client.load(DESKTOP)
	local key: any = rig.config.key
	local Ghost: any = rig.Ghost
	local step: { [string]: number } = rig.shared.step
	local width: number = step.radius + step.radius
	rig.workspace.CurrentCamera.CFrame = roblox.CFrame.new(0, EYE_HEIGHT, 0)
	rig.start()

	-- 1) Switched off it holds its key alone, draws nothing and sends nothing, and a key the game took switches nothing
	local idle: Client.Listening = rig.listening()
	rig.press(key, true)
	if idle.keys ~= 1 or idle.frames + idle.spawned + idle.despawned + idle.ghosts ~= 0 then
		return false, `Switched off it held {idle.keys} keys, {idle.frames} frames and {idle.ghosts} ghosts listeners`
	elseif #rig.buttons ~= 0 or rig.workspace:FindFirstChild(rig.config.drawn) or #rig.asks ~= 0 then
		return false, "Switched off on a desktop it made a button, drew or asked"
	elseif Ghost.readings() ~= nil or rig.listening().frames ~= 0 then
		return false, "A key the game took switched the ghosts on"
	end

	-- 2) Nine bots drawn before the switch and eight after it: the first frame asks for the 16 bots nearest the camera,
	-- leaving out the local player's nearer slot, the NPC, the one with no pose, the rider and the 17th
	rig.spawn(OWN, rig.player)
	rig.pose(OWN, vector.create(0, 0, -3))
	rig.spawn(NPC, nil, "Npc")
	rig.pose(NPC, vector.create(0, 0, -4))
	rig.spawn(UNPOSED)
	rig.spawn(RIDER)
	rig.pose(RIDER, vector.create(0, 0, -6), "Stand", 1)
	rig.pose(UNDRAWN, vector.create(0, 0, -8))

	for index: number = 1, BOTS do
		rig.pose(index, along(index))
		if index < 10 then
			rig.spawn(index)
		end
	end

	rig.clock(START)
	rig.press(key)
	for index: number = 10, BOTS do
		rig.spawn(index)
	end

	rig.frame(START)
	local first: string, twice: boolean = listed(rig.asks[1] or {})
	local on: Client.Listening = rig.listening()
	if #rig.asks ~= 1 or first ~= bots(16) or twice then
		return false, `The first frame asked {#rig.asks} times, first for {first}, not once for {bots(16)}`
	elseif on.frames ~= 1 or on.spawned ~= 1 or on.despawned ~= 1 or on.ghosts ~= 1 or on.keys ~= 1 then
		return false, `Switched on it held {on.frames} frames, {on.spawned} spawn and {on.ghosts} ghosts listeners`
	end

	-- 3) A change asks again only 0.25 s after the last ask, and an unchanged set asks nothing
	rig.despawn(3)
	rig.frame(START + 0.125)
	if #rig.asks ~= 1 then
		return false, "A change 0.125 s after an ask asked again at once"
	end

	rig.frame(START + 0.25)
	rig.frame(START + 0.5)
	local second: string = listed(rig.asks[2] or {})
	if #rig.asks ~= 2 or second ~= bots(BOTS, 3) then
		return false, `After slot 3 went the frames asked {#rig.asks - 1} more times, last for {second}`
	end

	-- 4) A box for each drawn slot the newest message names, at the server's feet carried on by its velocity to now,
	-- the hull of the drawn posture; none for the slot the client doesn't draw, nor for the drawn slot left out
	local now: number = START + 0.5
	rig.pose(2, along(2), "Crouch")
	rig.send(100, now - LEAD, LABEL, {
		ghost(1, vector.create(2, 0, -10), vector.create(SPRINT, 0, 0)),
		ghost(2, along(2), vector.zero),
		ghost(UNDRAWN, vector.create(0, 0, -8), vector.zero),
	})
	rig.frame(now)

	local sprinter: any, sprinterBox: any = box(rig, 1)
	local croucher: any, croucherBox: any = box(rig, 2)
	local runAt: vector = vector.create(2 + SPRINT * LEAD, step.standing / 2, -10)
	local crouchAt: vector = vector.create(0, step.crouched / 2, -SPACING * 2)
	if not sprinter or not placed(sprinter, sprinterBox, runAt, vector.create(width, step.standing, width)) then
		local size: any = sprinterBox and sprinterBox.Size
		return false, `Slot 1's box stood at {sprinter and sprinter.CFrame.Position} sized {size}, not at {runAt}`
	elseif not croucher or not placed(croucher, croucherBox, crouchAt, vector.create(width, step.crouched, width)) then
		local size: any = croucherBox and croucherBox.Size
		return false, `Slot 2's box stood at {croucher and croucher.CFrame.Position} sized {size}, not at {crouchAt}`
	elseif box(rig, UNDRAWN) or box(rig, 4) then
		return false, "A box was drawn for a slot the client doesn't draw or the message didn't name"
	end

	-- 5) A newer message that no longer names slot 1 takes its box at once, and slot 2's goes 0.5 s after the message
	-- that last named it once no more come. The readout, refreshed on that frame, names the server's state
	local heard: number = now + 0.125
	rig.clock(heard)
	rig.send(101, heard - LEAD, LABEL, { ghost(2, along(2), vector.zero) })
	rig.frame(heard)
	if box(rig, 1) or not box(rig, 2) then
		return false, "After a message naming slot 2 alone, slot 1 kept its box or slot 2 lost its own"
	end

	local screen: any = rig.playerGui:FindFirstChild(rig.config.drawn)
	local readout: any = screen and screen:FindFirstChildOfClass("TextLabel")
	if not readout or not string.find(readout.Text, `Ghosts, server: {LABEL}`, 1, true) then
		return false, `The readout showed {readout and readout.Text}, without the server's label {LABEL}`
	end

	rig.frame(heard + 0.375)
	if not box(rig, 2) then
		return false, "Slot 2's box went 0.375 s after its last message"
	end

	rig.frame(heard + rig.config.linger)
	if box(rig, 2) then
		return false, `Slot 2's box stayed {rig.config.linger} s after its last message`
	end

	-- 6) The lag, its parts and the ghost nearest the crosshair read every refresh, and a new label starts each mean
	-- again: each frame a message for tick k stamped LEAD before it, and the render time half a tick before k
	rig.pose(2, along(2))
	rig.set.delay = DELAY
	local start: number = START + 2
	local spacing: number = 0.125 -- Seconds between the frames, past the readout's refresh
	local function tick(k: number, at: number, label: string)
		rig.clock(at)
		rig.send(k, at - LEAD, label, { ghost(1, vector.create(2, 0, -10), vector.create(SPRINT, 0, 0)) })
		rig.set.renderTime = k - 0.5
		rig.frame(at)
	end

	for index: number = 0, 2 do
		tick(200 + index, start + index * spacing, LABEL)
	end

	local readings: any = Ghost.readings()
	local lag: number = (LEAD + spacing / 2) * MILLISECONDS
	local interpolation: number = DELAY * MILLISECONDS
	local ping: number = rig.player:GetNetworkPing() / 2 * MILLISECONDS
	local gap: number = 2 + SPRINT * LEAD
	if not readings or readings.lag.count ~= 3 or math.abs(readings.lag.last - lag) > CLOSE * MILLISECONDS then
		local count: number? = readings and readings.lag.count
		local last: number? = readings and readings.lag.last
		return false, `Three refreshes read the lag {count} times, last as {last} ms, not 3 times and {lag} ms`
	elseif math.abs(readings.rest.last - (lag - interpolation - ping)) > CLOSE * MILLISECONDS then
		return false, `The rest read {readings.rest.last} ms, not the lag less {interpolation} and {ping} ms`
	elseif readings.slot ~= 1 or readings.speed.last ~= SPRINT or math.abs(readings.gap.last - gap) > CLOSE then
		return false, `The crosshair's ghost read as slot {readings.slot} at {readings.speed.last} studs/s`
	elseif math.abs(readings.lead.last - gap / SPRINT * MILLISECONDS) > CLOSE * MILLISECONDS then
		return false, `The gap over the speed read {readings.lead.last} ms, not {gap / SPRINT * MILLISECONDS}`
	end

	tick(203, start + 3 * spacing, NEXT_LABEL)
	local relabeled: any = Ghost.readings()
	if not relabeled or relabeled.label ~= NEXT_LABEL or relabeled.lag.count ~= 1 or relabeled.speed.count ~= 1 then
		return false, `After the label changed the lag had {relabeled and relabeled.lag.count} readings, not 1`
	end

	-- 7) Off sends one empty ask and lets go of everything but the key; a message queued while off answered an ask
	-- from before and draws nothing when the switch goes on again, where every mean starts again
	local asked: number = #rig.asks
	rig.press(key)
	local off: Client.Listening = rig.listening()
	if #rig.asks ~= asked + 1 or #rig.asks[#rig.asks] ~= 0 then
		return false, `Switching off asked {#rig.asks - asked} times, last for {#rig.asks[#rig.asks]} slots`
	elseif off.keys ~= 1 or off.frames + off.spawned + off.despawned + off.ghosts ~= 0 or Ghost.readings() then
		return false, "Switched off it still held a frame, spawn or ghosts listener, or its readings"
	elseif rig.workspace:FindFirstChild(rig.config.drawn) or rig.playerGui:FindFirstChild(rig.config.drawn) then
		return false, "Switched off its boxes or its readout stayed"
	end

	local later: number = start + 1
	rig.send(300, later - LEAD, NEXT_LABEL, { ghost(1, vector.create(2, 0, -10), vector.zero) })
	rig.clock(later + 0.5)
	rig.press(key)
	rig.frame(later + 0.5)

	local again: any = Ghost.readings()
	if box(rig, 1) or not again or again.label ~= "" or again.lag.count + again.speed.count ~= 0 then
		return false, "A message queued while off drew a box or was read once the switch went on again"
	end

	-- 8) A touch screen with no keyboard has one button right of the live panel's, whose taps switch the ghosts
	local phone: Client.Rig = Client.load(PHONE)
	phone.start()
	local button: any = phone.buttons[1]
	local at: any = phone.config.button
	if #phone.buttons ~= 1 or button.Text ~= "Ghost" or button.Position ~= at then
		return false,
			`A touch screen with no keyboard made {#phone.buttons} buttons, the first at {button and button.Position}`
	elseif at.X.Scale ~= 0.5 or at.X.Offset ~= 56 or at.Y.Scale ~= 0 or at.Y.Offset ~= 8 then
		return false, `The touch button stands at {at}, not 8 pixels right of the live panel's 96-pixel button`
	elseif button.AnchorPoint.X ~= 0 or button.Parent.Parent ~= phone.playerGui then
		return false, "The touch button isn't anchored at its top left in a screen of the player's own"
	end

	phone.tap(button)
	local tapped: boolean = phone.Ghost.readings() ~= nil and phone.listening().frames == 1
	phone.tap(button)
	if not tapped or phone.Ghost.readings() ~= nil or phone.listening().frames ~= 0 then
		return false, "Two taps on the touch button did not switch the ghosts on and off"
	end

	for _, device: Client.Device in { DESKTOP, TOUCH_LAPTOP } do
		local keyed: Client.Rig = Client.load(device)
		keyed.start()
		if #keyed.buttons ~= 0 then
			return false, `A keyboard device, touch {device.touch}, made {#keyed.buttons} touch buttons`
		end
	end

	-- 9) G is written into the dev client once, in the ghosts' block, and drives none of the dev input
	local names: { string } = {}
	keyNames(CLIENT, names)

	local written: number = 0
	for _, name: string in names do
		if name == key.Name then
			written += 1
		end
	end

	if key.Name ~= "G" or written ~= 1 then
		return false, `The ghosts' key {key.Name} is written {written} times into the dev client, not once`
	end

	local place: Harness.Game = Harness.new()
	local Input: any = place.load(INPUT)
	local Command: any = place.tread("Codec.Command")
	local pressed: any = Input.new()
	local rest: any = Input.new()
	pressed:press(key.Name, true)

	local held: any = Command.new()
	local idleCommand: any = Command.new()
	pressed:sample(held)
	rest:sample(idleCommand)

	for field: string, value: any in held do
		if type(value) ~= "table" and value ~= idleCommand[field] then
			return false, `The ghosts' key {key.Name} drives the dev input's {field}`
		end
	end

	return true, nil
end
