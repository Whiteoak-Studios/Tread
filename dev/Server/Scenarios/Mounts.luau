--[[
    Checks the dev place against dev.project.json: Tread, Volt and Promise in
    ReplicatedStorage.Packages with Volt's runtime requiring, the fixtures in
    ServerScriptService, no auto-loading characters and streaming integrity off
--]]

--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PACKAGES: { string } = { "Tread", "Volt", "Promise" } -- What a game's install puts in Packages side by side
local STREAMING_INTEGRITY_MODE: Enum.StreamingIntegrityMode = Enum.StreamingIntegrityMode.Disabled
local SEPARATOR: string = "; " -- Between the problems in one report

return function (): (boolean, string | nil)
	local problems: { string } = {}

	local packages: Instance? = ReplicatedStorage:FindFirstChild("Packages")
	if not packages then
		table.insert(problems, "ReplicatedStorage.Packages is missing")
	else
		for _, name: string in PACKAGES do
			if not packages:FindFirstChild(name) then
				table.insert(problems, `ReplicatedStorage.Packages.{name} is missing`)
			end
		end

		local volt: Instance? = packages:FindFirstChild("Volt")
		if volt and not volt:IsA("ModuleScript") then
			table.insert(problems, `ReplicatedStorage.Packages.Volt is a {volt.ClassName}, not a ModuleScript`)
		elseif volt then
			local loaded: boolean, reason: any = pcall(require, volt)
			if not loaded then
				table.insert(problems, `Volt's runtime failed to require: {reason}`)
			end
		end
	end

	if not ServerScriptService:FindFirstChild("Fixtures") then
		table.insert(problems, "ServerScriptService.Fixtures is missing")
	end

	if Players.CharacterAutoLoads then
		table.insert(problems, "Players.CharacterAutoLoads is on")
	end

	-- A Rojo serve never writes this property, so only this check catches a place that drifts from the project file
	local mode: Enum.StreamingIntegrityMode = Workspace.StreamingIntegrityMode
	if mode ~= STREAMING_INTEGRITY_MODE then
		local found: string = `Workspace.StreamingIntegrityMode is {mode.Name}`
		local expected: string = `expected {STREAMING_INTEGRITY_MODE.Name}`
		local cause: string = "it is set in Studio by hand, because a Rojo serve never writes it"
		table.insert(problems, `{found}, {expected}: {cause}`)
	end

	if #problems > 0 then
		return false, table.concat(problems, SEPARATOR)
	end

	return true, nil
end
