--[[
    The per-server speed figure a benchmark run opens with: a fixed native
    loop and a fixed batch of Blockcasts at a part it lays far from every
    load, each timed in microseconds an operation, beside the Heartbeats
--]]

--!strict
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ServerScriptService.Server.Bots.Config)
local Work = require(ServerScriptService.Server.Parallel.Work)

local SETTINGS: Config.Calibration = require(ServerScriptService.Server.Bots.Config).calibration
local MICROSECONDS: number = 1e6 -- A second's
local P50: number = 0.5
local P95: number = 0.95
local FIGURE: string = "%.3f" -- Each time as the line prints it
local RATE: string = "%.2f" -- The Heartbeats a second
local PART: string = "Calibration" -- The name of the part the casts hit

-- What the timing gave: each sample's microseconds an operation, and the Heartbeats it spanned
export type Measured = {
	loop: { number }, -- A pass of the native loop
	casts: { number }, -- A Blockcast
	bytes: number, -- The buffer each pass went over
	frames: number, -- Heartbeats waited between samples
	seconds: number, -- From the first sample to the last
}

local Calibration = {}

-- The value a share of the samples are at or under, by nearest rank, 0 for none. It sorts the list in place
local function rank(samples: { number }, share: number): number
	if #samples == 0 then
		return 0
	end

	table.sort(samples)

	return samples[math.max(1, math.ceil(#samples * share))]
end

local function figure(value: number): string
	return string.format(FIGURE, value)
end

-- Times each sample of work in microseconds an operation, waiting a Heartbeat after every perFrame, and counts them
local function sample(times: { number }, operations: number, work: () -> ()): number
	local frames: number = 0

	for index: number = 1, SETTINGS.samples do
		local began: number = os.clock()
		work()
		times[index] = (os.clock() - began) * MICROSECONDS / operations

		if index % SETTINGS.perFrame == 0 then
			RunService.Heartbeat:Wait()
			frames += 1
		end
	end

	return frames
end

--[[
    The timing on the part laid: the settings checked and one cast that
    must hit the part, then the native loop's samples and the casts', each
    sample the same fixed work
--]]

local function measure(part: BasePart): Measured
	Calibration.check(SETTINGS)

	local params: RaycastParams = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }

	-- Each block starts drop studs above the part's top and is cast down twice as far, so it meets the top
	local lift: number = (SETTINGS.part.Y + SETTINGS.block.Y) / 2 + SETTINGS.drop
	local origin: CFrame = CFrame.new(SETTINGS.at + Vector3.new(0, lift, 0))
	local direction: Vector3 = Vector3.new(0, -2 * SETTINGS.drop, 0)
	local block: Vector3 = SETTINGS.block

	if not Workspace:Blockcast(origin, block, direction, params) then
		error("a Blockcast missed the part it was cast at", 0)
	end

	local data: buffer = buffer.create(SETTINGS.bytes)
	local passes: number = SETTINGS.passes
	local casts: number = SETTINGS.casts
	local measured: Measured = { loop = {}, casts = {}, bytes = SETTINGS.bytes, frames = 0, seconds = 0 }
	local started: number = os.clock()

	measured.frames += sample(measured.loop, passes, function ()
		Work.spin(data, passes)
	end)

	measured.frames += sample(measured.casts, casts, function ()
		for _ = 1, casts do
			Workspace:Blockcast(origin, block, direction, params)
		end
	end)

	measured.seconds = os.clock() - started

	return measured
end

--[[
    Refuses settings whose counts are not each a whole number from 1,
    naming one that isn't
--]]

function Calibration.check(settings: Config.Calibration)
	local counts: { [string]: number } = {
		samples = settings.samples,
		perFrame = settings.perFrame,
		bytes = settings.bytes,
		passes = settings.passes,
		casts = settings.casts,
	}

	for key: string, count: number in counts do
		if not (count >= 1) or count % 1 ~= 0 then
			error(`The calibration's {key} is a whole number from 1, not {count}`, 2)
		end
	end
end

--[[
    The calibration's line: the native loop's microseconds a pass and the
    Blockcasts' a cast at p50 and p95, the samples, and the Heartbeats a
    second while it ran. It sorts the samples in place
--]]

function Calibration.line(measured: Measured): string
	local rate: number = measured.seconds > 0 and measured.frames / measured.seconds or 0
	local loop: string = `{figure(rank(measured.loop, P50))}/{figure(rank(measured.loop, P95))}`
	local casts: string = `{figure(rank(measured.casts, P50))}/{figure(rank(measured.casts, P95))}`
	local spread: string = `{#measured.loop} samples each over {figure(measured.seconds)} s`

	local looped: string = `native loop µs a pass of {measured.bytes} B p50/p95 {loop}`
	local cast: string = `Blockcast µs a cast p50/p95 {casts}`
	local beats: string = `{spread} at {string.format(RATE, rate)} Heartbeats a second`

	return `{looped}; {cast}; {beats}`
end

--[[
    Times the workload at a part laid for it and removed after, whatever
    happened, and gives its line, or false with why it could not
--]]

function Calibration.run(): (boolean, string)
	local part: Part = Instance.new("Part")
	part.Name = PART
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Size = SETTINGS.part
	part.CFrame = CFrame.new(SETTINGS.at)
	part.Parent = Workspace

	local ran: boolean, result: any = pcall(measure, part)
	part:Destroy()

	if not ran then
		return false, `the calibration stopped: {result}`
	end

	return true, Calibration.line(result)
end

return Calibration
