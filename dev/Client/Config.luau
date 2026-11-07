--[[
    The dev game's client settings that are plain values: Frontier Zero's
    remote smoothing, ragdoll, correction, draw distance and detail numbers,
    with stand-ins where Frontier Zero has set none
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
}
