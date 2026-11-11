--[[
    Dev client values: Frontier Zero's remote smoothing, ragdoll, correction,
    draw distance and detail numbers, stand-ins where it sets none, and the dev
    place's view, keys, prompt, shooter, replay, kit, panel and G5 cost window
--]]

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages

local Tread = require(Packages.Tread)

local HANDHELD_DISTANCE: number = 500 -- Studs, standing in for the phone's and tablet's, which wait on the S22's run

-- Tilt and twist per joint, in degrees, each its ball socket's own three, standing in for the values Frontier Zero
-- tunes in its Studio test
local JOINT_LIMITS: JointLimits = {
	Waist = { tilt = 30, twistLower = -30, twistUpper = 30 },
	Neck = { tilt = 45, twistLower = -45, twistUpper = 45 },
	LeftShoulder = { tilt = 110, twistLower = -85, twistUpper = 85 },
	LeftElbow = { tilt = 5, twistLower = -120, twistUpper = -5 },
	LeftWrist = { tilt = 45, twistLower = -45, twistUpper = 45 },
	RightShoulder = { tilt = 110, twistLower = -85, twistUpper = 85 },
	RightElbow = { tilt = 5, twistLower = -120, twistUpper = -5 },
	RightWrist = { tilt = 45, twistLower = -45, twistUpper = 45 },
	LeftHip = { tilt = 60, twistLower = -30, twistUpper = 30 },
	LeftKnee = { tilt = 5, twistLower = -120, twistUpper = -5 },
	LeftAnkle = { tilt = 30, twistLower = -15, twistUpper = 15 },
	RightHip = { tilt = 60, twistLower = -30, twistUpper = 30 },
	RightKnee = { tilt = 5, twistLower = -120, twistUpper = -5 },
	RightAnkle = { tilt = 30, twistLower = -15, twistUpper = 15 },
}

type ClientSettings = Tread.ClientSettings
type JointLimits = index<index<ClientSettings, "bodies">, "jointLimits">

return {
	interpolation = {
		delay = 0.15, -- Seconds, where the adaptive delay starts
		delayMax = 0.25, -- Past this the client snaps
		scaleMin = 0.95,
		scaleMax = 1.05,
	},

	bodies = {
		radius = 250, -- Farther than this when the death arrives, the body lies
		late = 6, -- Reached later than this after the death, the body lies
		minSeconds = 1,
		maxSeconds = 6,
		check = 0.5,
		settleSpeed = 0.33, -- Every part slower than this freezes the body
		pushSpeed = 6,
		pushUpBias = 0.5,
		jointLimits = JOINT_LIMITS,
	},

	-- What a spectating moderator outlines every other player with through walls, standing in where Frontier Zero's
	-- Moderation sets none
	spectate = {
		outline = {
			fill = Color3.fromRGB(255, 60, 60),
			fillTransparency = 0.75, -- Mostly see-through, so the body still reads under it
			outline = Color3.fromRGB(255, 255, 255),
			outlineTransparency = 0,
		},
	},

	smoothing = {
		decay = 15, -- How fast the visual error offset shrinks, per second
		snap = 2, -- Studs: a correction larger than this snaps
	},

	drawDistance = {
		desktop = 1000,
		console = 1000,
		phone = HANDHELD_DISTANCE,
		tablet = HANDHELD_DISTANCE,
	},

	lod = {
		full = 128, -- Studs inside which a rig animates in full
		footIk = 128,
		aim = 600, -- Remote aim pitch shows inside this, and lean wherever a character is drawn
	},

	-- Standing in where Frontier Zero tunes its own with its rig and field of view
	firstPerson = {
		back = 1, -- Studs the first-person copy is drawn behind the world rig, so its torso sits behind the camera
	},

	-- The dev place's own shoulder view on V, standing in where Frontier Zero's camera sets none
	view = {
		side = 1.6, -- Studs right of the eye, just past the right shoulder of the 2.78-stud hull
		up = 0.4, -- Studs above the eye
		back = 6.5, -- Studs behind the eye along the look, about one and a third body heights
		blend = 0.25, -- Seconds a switch from one view to the other takes
		radius = 0.5, -- Studs of the sphere the view is cast with, so it stops that far short of a wall
	},

	-- The prompt shown while a jump press would start a mantle
	prompt = {
		text = "Jump to mantle",
		wait = 10, -- Seconds it waits at boot for the player's PlayerGui
	},

	-- The render distances this key cycles through, from the device's draw distance, and the label showing the one set
	render = {
		key = Enum.KeyCode.R, -- Bound to nothing else in the dev place
		distances = { 1000, 500, 250 }, -- Studs
		text = "Render distance: %g", -- The distance fills it
		wait = 10, -- Seconds the label waits at boot for the player's PlayerGui
	},

	-- The test elevator's call button, pressed by a ray from the eye along the look on this key
	elevator = {
		key = Enum.KeyCode.E, -- Bound to nothing else in the dev place
	},

	-- G7's shooter, while the dev server's shoot names a hotbar slot
	shots = {
		every = 2, -- Ticks from one shot to the next, 10 a second at the 20 Hz tick
		spread = 1.5, -- Studs either way along each axis a shot's aim is thrown off the target's body by
		seed = 1, -- What the throw is drawn from, again at each shoot, so a run repeats its aims
		lead = true, -- Whether a shot leads its target by the drawn velocity times the flight time
	},

	-- The replay of the clips the dev server's Playback scenario sends, on keys nothing else in the dev place binds
	replay = {
		keys = {
			play = Enum.KeyCode.P, -- Plays the newest clip, then pauses it and plays it again
			slower = Enum.KeyCode.M, -- Moves the speed on through speeds
			back = Enum.KeyCode.Comma, -- One relay tick back, paused
			forward = Enum.KeyCode.Period, -- One relay tick on, paused
			rewind = Enum.KeyCode.Left, -- A seek back
			skip = Enum.KeyCode.Right, -- A seek on
			stop = Enum.KeyCode.X, -- Ends the playback, and the live view comes back
		},

		speeds = { 1, 0.5, 0.25 }, -- What the speed cycles through, the first the speed a clip starts at
		seek = 1, -- Seconds a seek moves
		labelWait = 10, -- Seconds the label waits at boot for the player's PlayerGui
		ready = "Clip ready: %s plays it", -- The play key's name fills it
		playing = "Clip %.2f / %.2f s at %gx%s", -- The time, the length, the speed and the paused text
		paused = ", paused",
	},

	-- The live-run panel on this key: a button for each run, which asks the dev server to start it, and its report
	live = {
		key = Enum.KeyCode.L, -- Bound to nothing else in the dev place
		wait = 10, -- Seconds the panel waits at boot for the player's PlayerGui
		size = Vector2.new(760, 400), -- Pixels across and down the panel
		list = 170, -- Pixels across the column of run buttons
		row = 24, -- Pixels down the status line and each button
		gap = 6, -- Pixels between the panel's parts
		bar = 8, -- Pixels across each scroll bar
		textSize = 14, -- The report's, at which its height is measured
	},

	-- G5's client cost: the window the dev server's ClientCost scenario opens, and what each client's line reads
	cost = {
		attribute = "ClientCost", -- The Workspace attribute the scenario sets to a window's label, and clears at its end
		longest = 180, -- Seconds a window measures at most, past the scenario's 120 s window, before it ends on its own
		limit = 2, -- Milliseconds of remote-character work a frame the lowest device's p95 is held to
		percentiles = { 0.5, 0.95, 0.99 }, -- The remote work's, as the line prints them
		fps = 0.1, -- The share the frame rate is read at
		drawn = 0.5, -- The share the rigs drawn are read at
	},

	-- The dev place's exploit kit: what its panel counts, what each tool does, and how the ESP draws
	exploits = {
		small = 0.1, -- Studs: a correction this far or less with no flag flipped counts small on the panel
		panelWait = 10, -- Seconds the panel waits at boot for the player's PlayerGui
		flySpeed = 30, -- Studs/s the fly moves the body along the look at
		speedFactor = 2, -- What the speed multiplies the walk, sprint and crouch speeds by
		teleport = 10, -- Studs the teleport moves the body ahead along the look
		ahead = 10, -- Ticks the ahead renumbers each Move's commands by, well past the shared table's ticks.ahead
		hold = 200, -- Moves the lag switch holds at most, 10 s at the relay's 20 Hz, the oldest dropped past it

		esp = {
			stale = 1, -- Seconds since a slot's last record past which its box greys out
			markerSeconds = 2, -- Seconds a footstep entry's marker shows
			markers = 32, -- The markers kept, each new footstep entry taking the oldest
			refresh = 0.1, -- Seconds between refreshes of each label's distance and age
			labelLift = 1.5, -- Studs above a box's top its label sits
			labelRange = math.huge, -- Studs a label shows out to
			markerRadius = 0.5, -- Studs
			anchorSize = Vector3.new(0.1, 0.1, 0.1), -- The invisible part each box and marker is adorned to
			boxTransparency = 0.6,
			markerTransparency = 0.2,
			countTransparency = 0.4, -- The count's background
			live = Color3.fromRGB(255, 70, 70),
			old = Color3.fromRGB(150, 150, 150), -- A box whose slot has sent nothing newer than stale
			footstep = Color3.fromRGB(255, 210, 60),
			background = Color3.fromRGB(0, 0, 0),
			labelSize = UDim2.fromOffset(220, 40),
			fill = UDim2.fromScale(1, 1),
			countAt = UDim2.fromOffset(16, 16),
			countSize = UDim2.fromOffset(320, 24),
			drawn = "Esp", -- The Workspace folder and the ScreenGui the ESP draws in
			steps = "Footsteps", -- The folder inside it the markers sit in
			ageFormat = "%.1f", -- A record's age to the tenth of a second

			-- What a label calls a life the slot table names no Player for, by its reveal's kind
			names = { Player = "Player", Npc = "NPC", Sleeper = "Sleeper", Body = "Body" } :: { [string]: string },
			bot = "Bot", -- A player's kind whose slot table entry names no Player
			unknown = "Unknown", -- A life with no Player and no reveal heard
		},

		-- What the hitboxes draw each character's hull, lying box and hit shapes with
		hitboxes = {
			hull = Color3.fromRGB(80, 170, 255), -- The collision hull's box
			lying = Color3.fromRGB(255, 170, 40), -- The lying box, for a downed, sleeping or dead body
			body = Color3.fromRGB(255, 255, 255), -- The body capsule
			zone = Color3.fromRGB(255, 70, 70), -- Each zone capsule
			boxTransparency = 0.75,
			capsuleTransparency = 0.45,
			anchorSize = Vector3.new(0.1, 0.1, 0.1), -- The invisible part each character's drawing is adorned to
			drawn = "Hitboxes", -- The Workspace folder the hitboxes draw in
		},
	},
}
