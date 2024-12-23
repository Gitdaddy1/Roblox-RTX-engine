
-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Disable all built-in lighting effects
Lighting.Brightness = 0
Lighting.Ambient = Color3.new(0, 0, 0)
Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
Lighting.GlobalShadows = false
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0

-- Remove skybox and atmosphere effects
for _, child in pairs(Lighting:GetChildren()) do
	if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("PostEffect") then
		child:Destroy()
	end
end

-- Disable all existing lights
for _, descendant in pairs(Workspace:GetDescendants()) do
	if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
		descendant.Enabled = false
	end
end

-- Variables
local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Wait for the player's character to load
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()

-- Settings
local skyColor = Color3.fromRGB(135, 206, 235) -- Sky blue color
local skyIntensity = 1 -- Adjust as needed
local maxDistance = 1000 -- Maximum distance for rays to ensure they reach the sky
local gammaCorrection = 2.2 -- For gamma correction

-- Level of Detail (LOD) Settings
local maxRays = 100 -- Maximum number of rays per point for high-quality lighting
local minRays = 20 -- Minimum number of rays per point for distant objects
local lodStartDistance = 50 -- Distance from the camera where LOD starts to reduce rays
local lodEndDistance = 500 -- Distance from the camera where rays reach minRays

-- Function to calculate number of rays based on distance (LOD)
local function calculateNumRays(distance)
	if distance <= lodStartDistance then
		return maxRays
	elseif distance >= lodEndDistance then
		return minRays
	else
		local t = (distance - lodStartDistance) / (lodEndDistance - lodStartDistance)
		return math.floor(maxRays * (1 - t) + minRays * t)
	end
end

-- Function to get the surface normal at the hit point
local function getSurfaceNormal(part, position)
	-- For simplicity, use the part's normal vector
	local normal = (position - part.Position).Unit
	return normal
end

-- Function to compute lighting for a single part
local function computeLightingForPart(part)
	local position = part.Position
	local surfaceNormal = getSurfaceNormal(part, position)
	local offsetPosition = position + surfaceNormal * 0.01 -- Small offset to prevent self-intersection

	-- Calculate distance from camera
	local distanceFromCamera = (camera.CFrame.Position - position).Magnitude

	-- Determine number of rays based on LOD
	local numRays = calculateNumRays(distanceFromCamera)

	local accumulatedColor = Color3.new(0, 0, 0)
	local validSamples = 0

	for i = 1, numRays do
		-- Generate random direction over the hemisphere oriented by the surface normal
		local randomVector = Vector3.new(
			math.random(-1000, 1000) / 1000,
			math.random(-1000, 1000) / 1000,
			math.random(-1000, 1000) / 1000
		).Unit

		if randomVector:Dot(surfaceNormal) > 0 then
			-- Only consider directions in the hemisphere above the surface
			local rayDirection = randomVector

			-- Raycast to check for occlusion
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = {part}
			rayParams.FilterType = Enum.RaycastFilterType.Blacklist
			rayParams.IgnoreWater = true

			local result = Workspace:Raycast(offsetPosition, rayDirection * maxDistance, rayParams)

			if not result then
				-- Ray reaches the sky
				accumulatedColor += skyColor
				validSamples = validSamples + 1
			end
		end
	end

	if validSamples > 0 then
		accumulatedColor = (accumulatedColor / validSamples) * skyIntensity
	else
		accumulatedColor = Color3.new(0, 0, 0)
	end

	-- Apply material properties
	local materialReflectance = part.Reflectance
	local materialColor = part.Color

	-- Modulate with the material color and apply reflectance
	accumulatedColor = Color3.new(
		accumulatedColor.R * materialColor.R * (1 - materialReflectance),
		accumulatedColor.G * materialColor.G * (1 - materialReflectance),
		accumulatedColor.B * materialColor.B * (1 - materialReflectance)
	)

	-- Apply gamma correction
	accumulatedColor = Color3.new(
		accumulatedColor.R ^ (1 / gammaCorrection),
		accumulatedColor.G ^ (1 / gammaCorrection),
		accumulatedColor.B ^ (1 / gammaCorrection)
	)

	-- Clamp color values to [0, 1]
	accumulatedColor = Color3.new(
		math.clamp(accumulatedColor.R, 0, 1),
		math.clamp(accumulatedColor.G, 0, 1),
		math.clamp(accumulatedColor.B, 0, 1)
	)

	-- Apply the calculated color to the part
	part.Color = accumulatedColor
end

-- Main function to compute lighting for all parts
local parts = {}

-- Gather all relevant parts once
local function gatherParts()
	parts = {}

	for _, obj in pairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Transparency < 1 then
			-- Optional: Set material to SmoothPlastic for consistency
			obj.Material = Enum.Material.SmoothPlastic
			table.insert(parts, obj)
			-- Ensure parts do not cast default shadows
			obj.CastShadow = false
		end
	end
end

-- Gather parts initially
gatherParts()

-- Function to update lighting
local function updateLighting()
	for _, part in ipairs(parts) do
		computeLightingForPart(part)
	end
end

-- Update lighting every frame
RunService.RenderStepped:Connect(function()
	updateLighting()
end)

-- Listen for new parts being added to the workspace
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Transparency < 1 then
		descendant.Material = Enum.Material.SmoothPlastic -- Optional
		table.insert(parts, descendant)
		descendant.CastShadow = false
	end
end)

-- Listen for parts being removed from the workspace
Workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("BasePart") then
		for i, part in ipairs(parts) do
			if part == descendant then
				table.remove(parts, i)
				break
			end
		end
	end
end)

-- Include player's character in the raycasting
-- Add character parts to the parts list
local function addCharacterParts(character)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			table.insert(parts, part)
			part.CastShadow = false
		end
	end
end

-- Initial addition of character parts
addCharacterParts(character)

-- Update character parts when character respawns
localPlayer.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	addCharacterParts(character)
end)
