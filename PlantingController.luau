local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local Packages = ReplicatedStorage.Shared.Packages
local Utils = ReplicatedStorage.Shared.Utils	
local PlantEffect = ReplicatedStorage.Assets.Ui.PlantEffect
local DirtModel = ReplicatedStorage.Assets.Models.Dirt

local Janitor = require(Packages.Janitor)
local PlantingUtil = require(Utils.Planting.PlantingUtil)
local Networker = require(Packages.Networker).client
local Audio = require(Packages.Audio)

local characterJanitor = Janitor.new()
local mouseJanitor = Janitor.new()
local effectJanitor = Janitor.new()
local effectTweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local dirtTweenInfo = TweenInfo.new(2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local canPlant = false
local lastTarget = nil
local Net

local PlantingController = {}

local function ResetMouseJanitor()
	if mouseJanitor then
		mouseJanitor:Cleanup()
	end
end

local function ResetEffectJanitor()
	if effectJanitor then
		effectJanitor:Cleanup()
	end
end

local function ResetCharacterJanitor()
	if characterJanitor then
		characterJanitor:Cleanup()
	end
end

local function ValidateInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.Gamepad1 then 
		return true
	else
		return false
	end
end

local function SetEffect(effect: SurfaceGui)
	effect.Enabled = true
	
	local imageLabel = effect:FindFirstChildWhichIsA("ImageLabel")
	if not imageLabel then return end
	
	imageLabel.Size = UDim2.fromScale(0.6, 0.6)

	local tween = TweenService:Create(imageLabel, effectTweenInfo, {Size = UDim2.fromScale(1, 1)})
	effectJanitor:Add(tween, "Cancel", "EffectTween")
	tween:Play()
	
	Audio.PlaySound("PlantHover")
end

local function ConnectDetection()
	ResetMouseJanitor()
	
	mouseJanitor:Add(
		RunService.Heartbeat:Connect(function()
			local target = Mouse.Target
			if not target then return end

			if target ~= lastTarget then
				ResetEffectJanitor()
				lastTarget = target
				canPlant = false

				if PlantingUtil.OwnsPlot(Player, target) then
					local effect = PlantEffect:Clone()
					effect.Parent = target
					effectJanitor:Add(effect, "Destroy", "PlantEffect")

					canPlant = true
					SetEffect(effect)
				end
			end
		end),
		
		"Disconnect"
	)
	
	mouseJanitor:Add(
		UIS.InputBegan:Connect(function(input, gpe)
			if gpe or not canPlant or not ValidateInput(input) then return end
			
			Net:fire("Plant", lastTarget)
		end),
		
		"Disconnect"
	)
end

local function OnCharacterAdded(character: Model)
	ResetCharacterJanitor()
	
	characterJanitor:Add(
		character.ChildAdded:Connect(function(child)
			if PlantingUtil.IsSeed(child) then
				ConnectDetection()
			end
		end),
		
		"Disconnect"
	)
	
	characterJanitor:Add(
		character.ChildRemoved:Connect(function(child)
			if PlantingUtil.IsSeed(child) then
				ResetMouseJanitor()
				ResetEffectJanitor()
				lastTarget = nil
			end
		end),
		
		"Disconnect"
	)
end

function PlantingController.PlantAnimation(_, plotPart: Part)
	if not DirtModel or not DirtModel.PrimaryPart then return end

	local dirtJanitor = Janitor.new()
	
	local clone = DirtModel:Clone()
	clone.Parent = plotPart

	dirtJanitor:Add(clone, "Destroy")

	local startCF = plotPart.CFrame * CFrame.new(0, -0.5, 0)
	local endCF   = plotPart.CFrame * CFrame.new(0, 0.5, 0)

	clone:PivotTo(startCF)

	local elapsed = 0
	local duration = dirtTweenInfo.Time
	
	Audio.PlaySound("Plant")

	dirtJanitor:Add(
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local easedAlpha = TweenService:GetValue(alpha, dirtTweenInfo.EasingStyle, dirtTweenInfo.EasingDirection)
			
			clone:PivotTo(startCF:Lerp(endCF, easedAlpha))

			if alpha >= 1 then
				for _, part in clone:GetDescendants() do
					if part:IsA("BasePart") then
						TweenService:Create(part, TweenInfo.new(1), {Transparency = 1}):Play()
					end
				end
				
				task.delay(1, function()
					dirtJanitor:Cleanup()
				end)
			end
		end),
		
		"Disconnect"
	)
end

function PlantingController.Init()
	
	Net = Networker.new(
		"Planting", 
		PlantingController
	)
	
	Player.CharacterAdded:Connect(OnCharacterAdded)

	if Player.Character then
		OnCharacterAdded(Player.Character)
	end
end

return PlantingController