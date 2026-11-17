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

-- A set of runs and their timing: each scenario in order, run once for every seed
export type Program = {
	scenarios: { string },
	seeds: { number },
	warmupSeconds: number,
	steadySeconds: number,
	startDelay: number, -- Seconds a live server waits after its first player joins, for every other device to join
	pauseSeconds: number, -- Between two runs, and between the last run and the probe
	parallelProbe: boolean, -- Whether a live server runs the dev place's ParallelProbe once the last run's bots are gone
}

-- The client's panel, which shows the run's status and the report to copy
export type Panel = {
	key: Enum.KeyCode, -- Shows and hides it
	wait: number, -- Seconds it waits at boot for the PlayerGui and the server's report
	size: Vector2, -- Pixels across and down
	row: number, -- Pixels down the status line
	gap: number, -- Pixels between its parts
	bar: number, -- Pixels across the report's scroll bar
	textSize: number, -- The report's, at which its height is measured
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
	doneAttribute: string,
	reportName: string,
	botsName: string,
	floorsName: string,

	sampleInterval: number,
	clientGraceSeconds: number,
	percentiles: { number },
	fpsPercentile: number,

	liveJoinTimeout: number,
	pollInterval: number,
	outputWait: number,

	program: string, -- The program a live server runs, by its name in programs
	programs: { [string]: Program },
	scenarios: { [string]: Scenario },
	floors: { Area },

	rigType: Enum.HumanoidRigType,
	templateTimeout: number,
	spawnHeight: number,
	moveThreshold: number,
	viewerSpacing: number,
	floorProbeHeight: number,
	floorThickness: number,

	panel: Panel,

	settings: { Setting },
}

return {}
