--[[
    The dev place's ghosts, on a key or a touch screen's button: a box where
    the server holds each player drawn nearest the camera, carried on to now,
    and a readout of how far the tick drawn stands behind the server's clock
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Packages = ReplicatedStorage.Packages
local Player = Players.LocalPlayer

local Tread = require(Packages.Tread)

local Network = require(ReplicatedStorage.Shared.Network.Client)

local Hulls = require(Packages.Tread.Step.Hulls)
local Math = require(Packages.Tread.Step.Math)
local State = require(Packages.Tread.Step.State)

-- Requiring it finds the module Tread's client already started, as the hitboxes do
local Interpolate = require(Packages.Tread.Client.Interpolate)

local GhostConfig = require(script.Parent.Config).ghost
local Shared = require(ReplicatedStorage.Shared.Dev.Config)

local KEY: Enum.KeyCode = GhostConfig.key
local BUTTON: UDim2 = GhostConfig.button
local WAIT: number = GhostConfig.wait
local SLOTS: number = GhostConfig.slots
local ASK_EVERY: number = GhostConfig.askEvery
local LINGER: number = GhostConfig.linger
local REFRESH: number = GhostConfig.refresh
local RING: number = GhostConfig.ring
local STILL: number = GhostConfig.still
local COLOR: Color3 = GhostConfig.color
local TRANSPARENCY: number = GhostConfig.transparency
local ANCHOR_SIZE: Vector3 = GhostConfig.anchorSize
local DRAWN: string = GhostConfig.drawn
local STEP: Settings = Shared.step -- The hull every box takes
local WIDTH: number = STEP.radius + STEP.radius -- Studs across a box
local INTERVAL: number = 1 / Shared.rates.relay -- Seconds a relay tick, which steps on from a stamp beside a missing one
local WRAP: number = 2 ^ 16 -- A relay tick is a u16
local MILLISECONDS: number = 1000 -- A second's, which every time the readout shows is in
local ONE_WAY: number = 0.5 -- The share of the network ping, a round trip, that a message spends on its way down
local BUTTON_ORDER: number = 1 -- The touch button's screen, drawn over the panels' wherever they meet, as theirs are
local TIME_FIGURE: string = "%.1f" -- Milliseconds and studs a second, as the readout shows them
local STUDS_FIGURE: string = "%.2f" -- Studs
local NO_LABEL: string = "no message yet" -- The server's state before its first message names one
local REST: string = "Rest (the server's send delay and a frame)" -- What the lag leaves past the delay and half the ping

type Settings = State.Settings
type Slot = Tread.Slot
type StepState = State.State

-- What the newest message that named a slot said of it
type Answer = {
	feet: vector, -- The server's, in world space
	velocity: vector, -- Studs a second, as the tick left it
	stamp: number, -- The server's clock at the start of the frame that ran the tick
	heard: number, -- The server's clock, as this client reads it, when the message came
	message: number, -- Which message it came in, counted from the switch going on
}

-- What draws one ghost: an invisible part at its box's center, turned by the drawn facing, and the box on it
type Visual = {
	anchor: Part,
	box: BoxHandleAdornment,
}

-- A figure's newest reading, and the sum and count its mean is taken from
export type Figure = {
	last: number,
	sum: number,
	count: number,
}

-- What the readout shows, every mean counted since the switch went on or the server's label last changed
export type Readings = {
	label: string, -- The server's state its newest message named, empty before one
	read: boolean, -- Whether the newest reading found a stamp beside the tick drawn
	lag: Figure, -- Milliseconds the tick drawn stands behind the server's clock
	interpolation: Figure, -- Milliseconds of it the interpolation delay makes
	ping: Figure, -- And half the network ping
	rest: Figure, -- And the rest: the server's send delay and a frame
	slot: number?, -- The ghost nearest the crosshair at the newest reading, nil for none
	speed: Figure, -- Its studs a second
	gap: Figure, -- Studs from its drawn feet to its ghost's
	lead: Figure, -- Milliseconds, the gap over the speed, read only while it moves at STILL or faster
}

local Running: Tread.Client? = nil -- From the start
local Gui: PlayerGui? = nil -- From the start
local Asked: { number } = {} -- The slots the server holds as this viewer's ask, nearest first, empty for none
local AskedAt: number = -math.huge -- The server's clock at the newest ask, an empty one too, which spaces the next

-- What the switch made and connected, while it is on
local Readings: Readings? = nil
local Drawn: Folder? = nil
local Screen: ScreenGui? = nil
local Label: TextLabel? = nil
local Frame: RBXScriptConnection? = nil
local Disconnects: { () -> () } = {} -- The spawn, despawn and ghosts listeners'
local OnAt: number = 0 -- The server's clock as the switch went on
local CheckedAt: number = -math.huge -- When the drawn players were last looked over for an ask
local RefreshAt: number = 0 -- When the readout reads next
local Messages: number = 0 -- Messages heard since the switch went on
local Rigged: { [number]: Slot } = {} -- Each slot the client draws a rig for, by its id
local Answers: { [number]: Answer } = {} -- By slot
local Visuals: { [number]: Visual } = {} -- By slot

-- The newest ticks received, each with its stamp, in a ring of RING with the newest at Head
local Ticks: { number } = {}
local Stamps: { number } = {}
local Head: number = 0

-- What the ask and each frame reuse
local Pose: StepState = State.new()
local Candidates: { number } = {}
local Distances: { [number]: number } = {}

local Ghost = {}

-- A figure with no reading
local function figure(): Figure
	return { last = 0, sum = 0, count = 0 }
end

-- Readings with no figure read, under the server's label given
local function fresh(label: string): Readings
	return {
		label = label,
		read = false,
		lag = figure(),
		interpolation = figure(),
		ping = figure(),
		rest = figure(),
		slot = nil,
		speed = figure(),
		gap = figure(),
		lead = figure(),
	}
end

local function add(into: Figure, value: number)
	into.last = value
	into.sum += value
	into.count += 1
end

local function mean(of: Figure): number
	return of.count > 0 and of.sum / of.count or 0
end

--[[
    The server's clock at a render time, from the ticks received and the
    stamps they came with: between the stamps of the two ticks around it,
    or a tick's interval on from the one of them that came, and nil while
    neither did. Each tick is a u16, so a render time matches it modulo
    65,536

    @ at | the render time, relay ticks with their fraction, unwrapped as the client's is
    @ interval | seconds a relay tick
--]]

function Ghost.serverTime(ticks: { number }, stamps: { number }, at: number, interval: number): number?
	local below: number = math.floor(at)
	local fraction: number = at - below
	local low: number = below % WRAP
	local high: number = (below + 1) % WRAP

	local from: number? = nil
	local to: number? = nil
	for index: number, tick: number in ticks do
		if tick == low then
			from = stamps[index]
		elseif tick == high then
			to = stamps[index]
		end
	end

	if from and to then
		return Math.lerp(from, to, fraction)
	elseif from then
		return from + fraction * interval
	elseif to then
		return to - (1 - fraction) * interval
	end

	return nil
end

-- Nearer the camera first, and the lower slot first of two as near
local function nearer(a: number, b: number): boolean
	local first: number = Distances[a]
	local second: number = Distances[b]

	return first < second or (first == second and a < b)
end

--[[
    The slots to ask for, in a new list: each player drawn but the local
    one, posed at the render time and off any platform, nearest the camera
    first, at most SLOTS of them
--]]

local function pick(eye: vector): { number }
	table.clear(Candidates)
	table.clear(Distances)

	for id: number, slot: Slot in Rigged do
		if slot.kind ~= "Player" or slot.player == Player then
			continue
		end

		-- Whiteoak TODO: a rider is drawn on its platform's copy in its platform's space, so it gets no ghost; placing
		-- it as the hitboxes do brings it in once a run reads the split with a player on the elevator
		local shown: boolean = Interpolate.pose(id, Pose)
		if shown and Pose.platform == 0 then
			Distances[id] = vector.magnitude(Pose.position - eye)
			table.insert(Candidates, id)
		end
	end

	table.sort(Candidates, nearer)

	return table.move(Candidates, 1, math.min(#Candidates, SLOTS), 1, {})
end

-- Whether two asks name the same slots, in any order
local function same(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end

	for _, slot: number in a do
		if not table.find(b, slot) then
			return false
		end
	end

	return true
end

local function ask(slots: { number }, now: number)
	Network.ghostAsk.fire(slots)
	Asked = slots
	AskedAt = now
end

--[[
    Asks for the slots pick gives once they differ from the ones asked,
    looking at most every ASK_EVERY seconds and never sooner than that
    after the newest ask, so no two asks go closer together than that but
    the switch's own empty one
--]]

local function check(now: number, eye: vector)
	if now - CheckedAt < ASK_EVERY or now - AskedAt < ASK_EVERY then
		return
	end

	CheckedAt = now

	local slots: { number } = pick(eye)
	if not same(slots, Asked) then
		ask(slots, now)
	end
end

--[[
    The server's ghosts of one tick: the tick and its stamp into the ring,
    and each ghost as its slot's newest answer, a new label starting every
    mean again. A message stamped before the switch went on answered an
    ask from before, queued while nothing listened, so it is dropped
--]]

local function heard(tick: number, time: number, label: string, ghosts: { Network.Ghost })
	local readings: Readings? = Readings
	if not readings or time < OnAt then
		return
	end

	if label ~= readings.label then
		Readings = fresh(label)
	end

	Head = Head % RING + 1
	Ticks[Head] = tick
	Stamps[Head] = time
	Messages += 1

	local now: number = Workspace:GetServerTimeNow()
	for _, ghost: Network.Ghost in ghosts do
		Answers[ghost.slot] = {
			feet = vector.create(ghost.x, ghost.y, ghost.z),
			velocity = vector.create(ghost.vx, ghost.vy, ghost.vz),
			stamp = time,
			heard = now,
			message = Messages,
		}
	end
end

-- A slot's ghost made, an invisible part nothing collides with, casts against or touches, and its box drawn over walls
local function build(slot: number, drawn: Folder): Visual
	local anchor: Part = Instance.new("Part")
	anchor.Name = `{slot}`
	anchor.Size = ANCHOR_SIZE
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = drawn

	local box: BoxHandleAdornment = Instance.new("BoxHandleAdornment")
	box.Adornee = anchor
	box.AlwaysOnTop = true
	box.AdornCullingMode = Enum.AdornCullingMode.Never
	box.Color3 = COLOR
	box.Transparency = TRANSPARENCY
	box.Parent = anchor

	local visual: Visual = { anchor = anchor, box = box }
	Visuals[slot] = visual

	return visual
end

-- A slot's answer forgotten and its ghost destroyed
local function drop(slot: number)
	Answers[slot] = nil

	local visual: Visual? = Visuals[slot]
	if visual then
		Visuals[slot] = nil
		visual.anchor:Destroy()
	end
end

--[[
    Places the ghost of each slot drawn off any platform that the newest
    message named, while that message is younger than LINGER: the hull of
    the drawn pose's posture, standing on the server's feet carried on by
    the velocity to now, turned by the drawn facing. Every other answer goes
    with its ghost. Gives the ghost nearest the crosshair by the angle off
    the look, its speed and the gap from its drawn feet, nil for none
--]]

local function draw(drawn: Folder, now: number, eye: vector, look: vector): (number?, number, number)
	local nearest: number? = nil
	local closest: number = -math.huge -- The nearest one's cosine off the look
	local speed: number = 0
	local gap: number = 0

	for slot: number, answer: Answer in Answers do
		local shown: boolean = Rigged[slot] ~= nil and answer.message == Messages and now - answer.heard < LINGER
		if shown then
			local posed: boolean = Interpolate.pose(slot, Pose)
			shown = posed and Pose.platform == 0
		end

		if not shown then
			drop(slot)
			continue
		end

		local at: vector = answer.feet + answer.velocity * (now - answer.stamp)
		local height: number = Hulls.height(Pose, STEP)
		local visual: Visual = Visuals[slot] or build(slot, drawn)
		visual.anchor.CFrame = CFrame.new(at.x, at.y + height / 2, at.z) * CFrame.Angles(0, Pose.facing, 0)
		visual.box.Size = Vector3.new(WIDTH, height, WIDTH)

		local toward: vector = Pose.position + vector.create(0, height / 2, 0) - eye
		local distance: number = vector.magnitude(toward)
		local cosine: number = distance > 0 and vector.dot(toward, look) / distance or 1
		if cosine > closest then
			closest = cosine
			nearest = slot
			speed = vector.magnitude(answer.velocity)
			gap = vector.magnitude(Pose.position - at)
		end
	end

	return nearest, speed, gap
end

--[[
    One reading: the lag of the tick drawn behind the server's clock and
    its three parts, while the ring holds a stamp beside the render time,
    and the speed, gap and gap over the speed of the ghost nearest the
    crosshair, the last only while it moves at STILL or faster
--]]

local function read(readings: Readings, client: Tread.Client, now: number, nearest: number?, speed: number, gap: number)
	local stamp: number? = Ghost.serverTime(Ticks, Stamps, client:getRenderTime(), INTERVAL)
	readings.read = stamp ~= nil

	if stamp then
		local lag: number = (now - stamp) * MILLISECONDS
		local interpolation: number = Interpolate.delay() * MILLISECONDS
		local ping: number = Player:GetNetworkPing() * ONE_WAY * MILLISECONDS
		add(readings.lag, lag)
		add(readings.interpolation, interpolation)
		add(readings.ping, ping)
		add(readings.rest, lag - interpolation - ping)
	end

	readings.slot = nearest
	if nearest then
		add(readings.speed, speed)
		add(readings.gap, gap)

		if speed >= STILL then
			add(readings.lead, gap / speed * MILLISECONDS)
		end
	end
end

local function timeOf(value: number): string
	return string.format(TIME_FIGURE, value)
end

local function studsOf(value: number): string
	return string.format(STUDS_FIGURE, value)
end

-- The readout's lines: the server's state, the lag and its parts, and the ghost nearest the crosshair
local function text(readings: Readings): string
	local label: string = readings.label ~= "" and readings.label or NO_LABEL
	local lines: { string } = { `Ghosts, server: {label}` }

	local lag: Figure = readings.lag
	local overall: string = `mean {timeOf(mean(lag))} over {lag.count}`
	if readings.read then
		local interpolation: Figure = readings.interpolation
		local ping: Figure = readings.ping
		local rest: Figure = readings.rest

		table.insert(lines, `Lag {timeOf(lag.last)} ms, {overall}`)
		table.insert(lines, `Interpolation {timeOf(interpolation.last)} ms, mean {timeOf(mean(interpolation))}`)
		table.insert(lines, `Half ping {timeOf(ping.last)} ms, mean {timeOf(mean(ping))}`)
		table.insert(lines, `{REST} {timeOf(rest.last)} ms, mean {timeOf(mean(rest))}`)
	else
		table.insert(lines, `Lag: no stamp beside the tick drawn, {overall}`)
	end

	local slot: number? = readings.slot
	if not slot then
		table.insert(lines, "No ghost near the crosshair")

		return table.concat(lines, "\n")
	end

	local speed: Figure = readings.speed
	local gap: Figure = readings.gap
	local lead: Figure = readings.lead
	local moving: string = speed.last >= STILL and `{timeOf(lead.last)} ms` or "still"
	table.insert(lines, `Slot {slot}: {timeOf(speed.last)} studs/s, mean {timeOf(mean(speed))}`)
	table.insert(lines, `Gap {studsOf(gap.last)} studs, mean {studsOf(mean(gap))} over {gap.count}`)
	table.insert(lines, `Gap/speed {moving}, mean {timeOf(mean(lead))} over {lead.count}`)

	return table.concat(lines, "\n")
end

--[[
    One drawn frame, after Tread's own, so it reads that frame's render time
    and poses: the ask, the ghosts, and every REFRESH seconds a reading and
    the readout
--]]

local function frame()
	local client: Tread.Client? = Running
	local readings: Readings? = Readings
	local drawn: Folder? = Drawn
	if not client or not readings or not drawn then
		error("The ghosts drew a frame while they were switched off")
	end

	local camera: Camera? = Workspace.CurrentCamera
	if not camera then
		return
	end

	local now: number = Workspace:GetServerTimeNow()
	local at: Vector3 = camera.CFrame.Position
	local ahead: Vector3 = camera.CFrame.LookVector
	local eye: vector = vector.create(at.X, at.Y, at.Z)
	local look: vector = vector.create(ahead.X, ahead.Y, ahead.Z)

	check(now, eye)

	local nearest: number?, speed: number, gap: number = draw(drawn, now, eye, look)
	if now < RefreshAt then
		return
	end

	RefreshAt = now + REFRESH
	read(readings, client, now, nearest, speed, gap)

	local label: TextLabel? = Label
	if label then
		label.Text = text(readings)
	end
end

--[[
    The readout, a label made in code at the bottom left of the screen just
    above the render distance's, in a screen of its own
--]]

local function readout(playerGui: PlayerGui): (ScreenGui, TextLabel)
	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = DRAWN
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	-- The render distance's label stands 28 pixels tall, 16 above the bottom edge, so this one ends 8 above it, tall
	-- enough for the readout's eight lines
	local label: TextLabel = Instance.new("TextLabel")
	label.Name = "Readout"
	label.Text = ""
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 16, 1, -52)
	label.Size = UDim2.fromOffset(540, 144)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 1
	label.Parent = screen

	return screen, label
end

--[[
    Turns the ghosts on: the ring, the answers and every mean start empty,
    the rigs drawn already are taken from the handle, since their spawns
    were told before anything listened, then the folder, the readout and
    the listeners, each disconnected again at the switch's off
--]]

local function switchOn(client: Tread.Client, playerGui: PlayerGui)
	local now: number = Workspace:GetServerTimeNow()
	OnAt = now
	CheckedAt = -math.huge
	RefreshAt = now
	Messages = 0
	Head = 0
	table.clear(Ticks)
	table.clear(Stamps)
	table.clear(Answers)
	table.clear(Rigged)
	Readings = fresh("")

	-- Tread's handle gives no list of the rigs it draws, so its own table is read once here
	local rigged: { [number]: Slot } = (client :: any)._rigged
	for id: number, slot: Slot in rigged do
		Rigged[id] = slot
	end

	local drawn: Folder = Instance.new("Folder")
	drawn.Name = DRAWN
	drawn.Parent = Workspace
	Drawn = drawn

	local screen: ScreenGui, label: TextLabel = readout(playerGui)
	Screen = screen
	Label = label

	table.insert(
		Disconnects,
		client:onSpawned(function (slot: Slot, _: Model)
			Rigged[slot.id] = slot
		end)
	)

	table.insert(
		Disconnects,
		client:onDespawned(function (slot: Slot)
			Rigged[slot.id] = nil
		end)
	)

	-- After OnAt is set, since the listener takes what queued while nothing listened as it connects
	table.insert(Disconnects, Network.ghosts.on(heard))
	Frame = RunService.PreRender:Connect(frame)
end

--[[
    Turns the ghosts off: every listener disconnected, all they drew
    destroyed, and one empty ask when the server holds one, so it sends
    nothing more
--]]

local function switchOff()
	for _, disconnect: () -> () in Disconnects do
		disconnect()
	end

	table.clear(Disconnects)

	local connection: RBXScriptConnection? = Frame
	if connection then
		connection:Disconnect()
	end

	local drawn: Folder? = Drawn
	if drawn then
		drawn:Destroy()
	end

	local screen: ScreenGui? = Screen
	if screen then
		screen:Destroy()
	end

	Readings = nil
	Frame = nil
	Drawn = nil
	Screen = nil
	Label = nil
	table.clear(Visuals)
	table.clear(Answers)
	table.clear(Rigged)
	table.clear(Ticks)
	table.clear(Stamps)

	if #Asked > 0 then
		ask({}, Workspace:GetServerTimeNow())
	end
end

-- Turns the ghosts on or off, on the key and the touch button alike
local function switch()
	local client: Tread.Client? = Running
	local playerGui: PlayerGui? = Gui
	if not client or not playerGui then
		error("The ghosts' switch ran before Ghost.start")
	end

	if Readings then
		switchOff()
	else
		switchOn(client, playerGui)
	end
end

--[[
    The button a touch screen with no keyboard turns the ghosts on and off
    by, always on screen in a screen of its own at the top edge, right of
    the live panel's own button there
--]]

local function touchButton(playerGui: PlayerGui): TextButton
	local screen: ScreenGui = Instance.new("ScreenGui")
	screen.Name = `{DRAWN}Button`
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = BUTTON_ORDER
	screen.Parent = playerGui

	local button: TextButton = Instance.new("TextButton")
	button.Name = "Toggle"
	button.Text = "Ghost"
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = BUTTON
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	button.BackgroundTransparency = 0.25
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 14
	button.ZIndex = 1
	button.Parent = screen

	return button
end

--[[
    Starts the ghosts once a client, switched off: the key, and on a touch
    screen with no keyboard the button, each for the client session, are
    all it holds until it is switched on. It waits at boot for the
    PlayerGui when it has not come yet
--]]

function Ghost.start(client: Tread.Client)
	if Running then
		error("Ghost.start runs once a client, and it has already run", 2)
	end

	local playerGui: PlayerGui? = Player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		-- Boot-time wait: the PlayerGui may not have arrived when the client's scripts start
		playerGui = Player:WaitForChild("PlayerGui", WAIT) :: PlayerGui?
	end

	if not playerGui then
		error(`The ghosts found no PlayerGui within {WAIT} s`)
	end

	Running = client
	Gui = playerGui

	-- A key typed into a focused box is processed, so G there switches nothing
	UserInputService.InputBegan:Connect(function (input: InputObject, processed: boolean)
		if not processed and input.KeyCode == KEY then
			switch()
		end
	end)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		touchButton(playerGui).Activated:Connect(switch)
	end
end

-- What the readout shows, nil while the ghosts are switched off
function Ghost.readings(): Readings?
	return Readings
end

return Ghost
