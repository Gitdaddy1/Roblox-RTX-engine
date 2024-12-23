-- Services so it can take control of the lighting engine 
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

-- Disable built-in lighting effects modify this to lighting brightness 0 but it will be very dark unless you crank up all the ray numbers lol
Lighting.Brightness = 0.2
Lighting.Ambient = Color3.new(0, 0, 0)
Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
Lighting.GlobalShadows = false
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0



local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Wait for the player's character to load
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()

-- settings
local sunDirection = Vector3.new(1, -1, 1).Unit -- Adjusted sun direction
local sunColor = Color3.fromRGB(255, 255, 224) -- Soft sunlight color
local sunIntensity = 100 -- Sun intensity
local skyColor = Color3.fromRGB(135, 206, 235) -- Sky blue color
local skyIntensity = 0.5 -- Sky intensity

local maxDistance = 50000 -- Maximum distance for rays
local gammaCorrection = 10 -- For gamma correction

-- LOD Settings
local maxRays = 100000 -- Maximum number of rays per point
local minRays = 10000 -- Minimum number of rays per point
local lodDistance = 200 -- Distance at which LOD reduces rays


local function getSurfaceNormal(part, position)
	if part:IsA("MeshPart") or part:IsA("UnionOperation") then
		-- Approximate normal for MeshParts and Unions
		local normal = (position - part.Position).Unit
		return normal
	else
		
		local relativePosition = part.CFrame:PointToObjectSpace(position)
		local halfSize = part.Size / 2

		local normals = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}

		local distances = {
			math.abs(halfSize.X - relativePosition.X),
			math.abs(-halfSize.X - relativePosition.X),
			math.abs(halfSize.Y - relativePosition.Y),
			math.abs(-halfSize.Y - relativePosition.Y),
			math.abs(halfSize.Z - relativePosition.Z),
			math.abs(-halfSize.Z - relativePosition.Z),
		}

		local minDistance = math.huge
		local normal = Vector3.new(0, 1, 0)

		for i = 1, 6 do
			if distances[i] < minDistance then
				minDistance = distances[i]
				normal = normals[i]
			end
		end

		return part.CFrame:VectorToWorldSpace(normal)
	end
end


local function computeLightingForPoint(part, position)
	local accumulatedColor = Color3.new(0, 0, 0)
	local surfaceNormal = getSurfaceNormal(part, position)

	
	local offsetPosition = position + surfaceNormal * 0.01

	
	local distanceFromCamera = (camera.CFrame.Position - position).Magnitude
	local numRays = maxRays

	if distanceFromCamera > lodDistance then
		numRays = math.max(minRays, math.floor(maxRays * (lodDistance / distanceFromCamera)))
	end

	-- Accumulate light from sky
	local skySamples = 10000000
	local skyLight = Color3.new(0, 0, 0)

	for i = 1, numRays do
		
		local u = math.random()
		local v = math.random()
		local theta = math.acos(math.sqrt(1 - u))
		local phi = 2 * math.pi * v

		local x = math.sin(theta) * math.cos(phi)
		local y = math.cos(theta)
		local z = math.sin(theta) * math.sin(phi)

		local randomDirection = Vector3.new(x, y, z)
		randomDirection = randomDirection.Unit

		
		local up = Vector3.new(0, 1, 0)
		local rotation = CFrame.fromAxisAngle(up:Cross(surfaceNormal), math.acos(up:Dot(surfaceNormal)))
		randomDirection = rotation:VectorToWorldSpace(randomDirection)

		
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {part, character}
		rayParams.FilterType = Enum.RaycastFilterType.Blacklist
		rayParams.IgnoreWater = true

		local result = Workspace:Raycast(offsetPosition, randomDirection * maxDistance, rayParams)

		if not result then
			-- Reaches the sky
			skyLight += skyColor
			skySamples = skySamples + 1
		end
	end

	if skySamples > 0 then
		skyLight = (skyLight / skySamples) * skyIntensity
		accumulatedColor += skyLight
	end

	
	local normalDotLight = math.max(0, surfaceNormal:Dot(-sunDirection))

	
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {part, character}
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	rayParams.IgnoreWater = true

	local sunOccluded = Workspace:Raycast(offsetPosition, -sunDirection * maxDistance, rayParams)

	local shadowFactor = 1

	if sunOccluded then
		shadowFactor = 0 -- In shadow
	end

	
	local materialReflectance = part.Reflectance
	local materialColor = part.Color

	
	local sunIntensityFactor = normalDotLight * sunIntensity * (1 - materialReflectance) * shadowFactor
	local sunLight = sunColor * sunIntensityFactor

	
	sunLight = Color3.new(
		sunLight.R * materialColor.R,
		sunLight.G * materialColor.G,
		sunLight.B * materialColor.B
	)

	accumulatedColor += sunLight

	
	accumulatedColor = Color3.new(
		accumulatedColor.R ^ (1 / gammaCorrection),
		accumulatedColor.G ^ (1 / gammaCorrection),
		accumulatedColor.B ^ (1 / gammaCorrection)
	)

	
	accumulatedColor = Color3.new(
		math.clamp(accumulatedColor.R, 0, 1),
		math.clamp(accumulatedColor.G, 0, 1),
		math.clamp(accumulatedColor.B, 0, 1)
	)

	return accumulatedColor
end


local parts = {}

-- Gather all relevant parts once
local function gatherParts()
	parts = {}

	for _, obj in pairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Transparency < 1 then
			-- Set material to SmoothPlastic for consistency (optional)
			obj.Material = Enum.Material.SmoothPlastic
			table.insert(parts, obj)
			-- Ensure parts do not cast default shadows
			obj.CastShadow = false
		end
	end
end


gatherParts()


local function updateLighting()
	for _, part in ipairs(parts) do
		-- Compute lighting for the part's position
		local partPosition = part.Position
		local color = computeLightingForPoint(part, partPosition)
		if color then
			part.Color = color
		end
	end
end


RunService.RenderStepped:Connect(function()
	updateLighting()
end)


Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Transparency < 1 then
		descendant.Material = Enum.Material.SmoothPlastic -- Optional
		table.insert(parts, descendant)
		descendant.CastShadow = false
	end
end)


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
local function addCharacterParts(character)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			table.insert(parts, part)
			part.CastShadow = false
		end
	end
end


addCharacterParts(character)

-- Update character parts when character respawns
localPlayer.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	addCharacterParts(character)
end)
