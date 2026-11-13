--[[
    The shape both arms' Config modules take, so one arm's code runs in the A0
    and A1 places and the type checker holds each config to it
--]]

--!strict
export type Area = {
	center: Vector3, -- The ground point at the area's middle
	size: Vector2, -- Its width along X and its depth along Z
}

export type Group = {
	count: number,
	spawn: Area,
	roam: Area?, -- nil keeps the group standing where it spawned
}

export type Scenario = {
	groups: { Group },
	viewer: Vector3?, -- Where each real player's character starts the run, nil leaves them where they are
}

export type Load = () -> () -> () -- Starts a run's load and hands back what stops it

export type Setting = {
	property: string, -- A Workspace property
	set: EnumItem | boolean, -- The value the arm's project file gives it
}

export type Config = {
	arm: string,

	runAttribute: string,
	steadyAttribute: string,
	reportName: string,
	botsName: string,
	floorsName: string,

	warmupSeconds: number,
	steadySeconds: number,
	sampleInterval: number,
	clientGraceSeconds: number,
	percentiles: { number },
	fpsPercentile: number,

	liveJoinTimeout: number,
	liveStartDelay: number,
	pauseSeconds: number,
	pollInterval: number,

	program: { string },
	seeds: { number },
	scenarios: { [string]: Scenario },
	floors: { Area },

	rigType: Enum.HumanoidRigType,
	templateTimeout: number,
	spawnHeight: number,
	moveThreshold: number,
	viewerSpacing: number,
	floorProbeHeight: number,
	floorThickness: number,

	settings: { Setting },
}

return {}
