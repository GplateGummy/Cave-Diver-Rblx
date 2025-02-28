-- Services
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")

-- Constants
local ActivationKey = Enum.KeyCode.KeypadFour
local BodyPositionP = 25000
local BodyPositionD = 2500
local OrientationResponsiveness = 25
local AnimationDuration = 1.5
local FinalHoldTime = 2.5
local MaxHeightMultiplier = 1.2
local MaxHeightCap = 25
local RaycastDistance = 150
local FinalOffset = Vector3.new(0, -1.5, -0.5)
local FinalRotation = CFrame.Angles(math.rad(-110), math.rad(0), math.rad(0))

-- Variables
local Debounce = false

-- Helper Functions
local function IsValidCharacter(Character)
	if not Character then return false end
	if not Character:IsA("Model") then return false end
	if not Character:FindFirstChildWhichIsA("Humanoid") then return false end
	if not Character:FindFirstChild("HumanoidRootPart") then return false end
	return true
end

local function GetHumanoid(Character)
	if not Character then return nil end
	return Character:FindFirstChildWhichIsA("Humanoid")
end

local function LockHumanoid(Humanoid)
	if not Humanoid then return end
	Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	Humanoid.PlatformStand = true
	Humanoid.AutoRotate = false
	Humanoid.EvaluateStateMachine = false
end

local function UnlockHumanoid(Humanoid)
	print("unlocking")
	if not Humanoid then return end
	Humanoid.PlatformStand = false
	Humanoid.AutoRotate = true
	Humanoid.EvaluateStateMachine = true
	task.wait(0.5)
	Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function SetupRaycast(LocalPlayer)
	local MousePosition = UserInputService:GetMouseLocation()
	local RayParams = RaycastParams.new()
	RayParams.FilterType = Enum.RaycastFilterType.Include

	local Characters = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= LocalPlayer and IsValidCharacter(Player.Character) then
			table.insert(Characters, Player.Character)
		end
	end

	if #Characters == 0 then return nil end

	RayParams.FilterDescendantsInstances = Characters

	local UnitRay = Camera:ViewportPointToRay(MousePosition.X, MousePosition.Y)
	return workspace:Raycast(UnitRay.Origin, UnitRay.Direction * RaycastDistance, RayParams)
end

local function CreateConstraints(PlayerHRP, StartPosition)
	local AnimAttachment = Instance.new("Attachment")
	AnimAttachment.Name = "AnimationAttachment"
	AnimAttachment.Parent = PlayerHRP

	local BodyPosition = Instance.new("BodyPosition")
	BodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	BodyPosition.P = BodyPositionP
	BodyPosition.D = BodyPositionD
	BodyPosition.Position = StartPosition
	BodyPosition.Parent = PlayerHRP

	local AlignOrientation = Instance.new("AlignOrientation")
	AlignOrientation.MaxTorque = math.huge
	AlignOrientation.MaxAngularVelocity = math.huge
	AlignOrientation.Responsiveness = OrientationResponsiveness
	AlignOrientation.Attachment0 = AnimAttachment
	AlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	AlignOrientation.Parent = PlayerHRP

	return {
		BodyPosition = BodyPosition,
		AlignOrientation = AlignOrientation,
		AnimAttachment = AnimAttachment
	}
end

local function CleanupAnimation(Connections, Constraints, PlayerHRP)
	for _, Connection in pairs(Connections) do
		if Connection then Connection:Disconnect() end
	end

	for _, Constraint in pairs(Constraints) do
		if Constraint and Constraint:IsDescendantOf(workspace) then
			Constraint:Destroy()
		end
	end

	if PlayerHRP and PlayerHRP:IsDescendantOf(workspace) and 
		PlayerHRP:FindFirstChild("AnimationAttachment") then
		PlayerHRP.AnimationAttachment:Destroy()
	end

	task.delay(0.3, function()
		Debounce = false
	end)
end

local function SetupEventConnections(LocalCharacter, TargetHRP, Constraints, PlayerHRP)
	local Connections = {}

	Connections.TargetAncestry = TargetHRP.AncestryChanged:Connect(function(_, Parent)
		if not Parent then
			CleanupAnimation(Connections, Constraints, PlayerHRP)
		end
	end)

	Connections.CharacterAncestry = LocalCharacter.AncestryChanged:Connect(function(_, Parent)
		if not Parent then
			CleanupAnimation(Connections, Constraints, PlayerHRP)
		end
	end)

	Connections.PlayerLeaving = Players.PlayerRemoving:Connect(function(Player)
		if Player == Players.LocalPlayer or (TargetHRP.Parent and Player.Character == TargetHRP.Parent) then
			CleanupAnimation(Connections, Constraints, PlayerHRP)
		end
	end)

	return Connections
end

local function PerformArcMovement(StartPosition, TargetPosition, Progress, MaxHeight)
	local ArcHeight = math.sin(Progress * math.pi) * MaxHeight
	local LerpPosition = StartPosition:Lerp(TargetPosition, Progress)
	return LerpPosition + Vector3.new(0, ArcHeight, 0)
end

local function PerformAnimation(PlayerHRP, PlayerHumanoid, TargetHRP)
	local StartPosition = PlayerHRP.Position

	LockHumanoid(PlayerHumanoid)

	local AttachmentExists = PlayerHRP:FindFirstChild("AnimationAttachment")
	if AttachmentExists then AttachmentExists:Destroy() end

	local ConstraintObjects = CreateConstraints(PlayerHRP, StartPosition)
	local Constraints = {ConstraintObjects.BodyPosition, ConstraintObjects.AlignOrientation, ConstraintObjects.AnimAttachment}

	local Connections = SetupEventConnections(PlayerHRP.Parent, TargetHRP, Constraints, PlayerHRP)

	local InitialTargetPosition = TargetHRP.Position
	local Distance = (InitialTargetPosition - StartPosition).Magnitude
	local MaxHeight = math.min(Distance * MaxHeightMultiplier, MaxHeightCap)

	local AnimationStartTime = tick()

	Connections.Movement = RunService.Heartbeat:Connect(function()
		if not PlayerHRP:IsDescendantOf(workspace) or not TargetHRP:IsDescendantOf(workspace) then
			CleanupAnimation(Connections, Constraints, PlayerHRP)
			return
		end

		local ElapsedTime = tick() - AnimationStartTime
		local Progress = math.min(ElapsedTime / AnimationDuration, 1)

		LockHumanoid(PlayerHumanoid)

		if Progress < 1 then
			local CurrentTargetPosition = TargetHRP.Position
			local ArcPosition = PerformArcMovement(StartPosition, CurrentTargetPosition, Progress, MaxHeight)

			ConstraintObjects.BodyPosition.Position = ArcPosition

			local LookCFrame = CFrame.lookAt(ArcPosition, CurrentTargetPosition)
			ConstraintObjects.AlignOrientation.CFrame = LookCFrame
		else
			Connections.Movement:Disconnect()

			if not PlayerHRP:IsDescendantOf(workspace) or not TargetHRP:IsDescendantOf(workspace) then
				CleanupAnimation(Connections, Constraints, PlayerHRP)
				return
			end

			Connections.FinalAnimation = RunService.Heartbeat:Connect(function()
				if not PlayerHRP:IsDescendantOf(workspace) or not TargetHRP:IsDescendantOf(workspace) then
					CleanupAnimation(Connections, Constraints, PlayerHRP)
					return
				end

				local FinalTargetPosition = TargetHRP.Position + FinalOffset
				ConstraintObjects.BodyPosition.Position = FinalTargetPosition

				local FinalCFrame = CFrame.new(FinalTargetPosition) * FinalRotation
				ConstraintObjects.AlignOrientation.CFrame = FinalCFrame

				LockHumanoid(PlayerHumanoid)
			end)

			task.delay(FinalHoldTime, function()
				CleanupAnimation(Connections, Constraints, PlayerHRP)


				local LocalPlayer = Players.LocalPlayer
				if LocalPlayer and LocalPlayer.Character then
					local Humanoid = GetHumanoid(LocalPlayer.Character)
					UnlockHumanoid(Humanoid)
				end
			end)
		end
	end)
end

UserInputService.InputBegan:Connect(function(Input)
	if Input.KeyCode ~= ActivationKey then return end
	if Debounce == true then return end

	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then return end

	local LocalCharacter = LocalPlayer.Character
	if not IsValidCharacter(LocalCharacter) then return end

	local PlayerHRP = LocalCharacter:FindFirstChild("HumanoidRootPart")
	if not PlayerHRP then return end

	local PlayerHumanoid = GetHumanoid(LocalCharacter)
	if not PlayerHumanoid then return end

	Debounce = true

	local RaycastResult = SetupRaycast(LocalPlayer)

	if not RaycastResult or not RaycastResult.Position or not RaycastResult.Instance then
		Debounce = false
		return
	end

	local CharacterModel = RaycastResult.Instance:FindFirstAncestorOfClass("Model")
	if not IsValidCharacter(CharacterModel) then
		Debounce = false
		return
	end

	local TargetHRP = CharacterModel:FindFirstChild("HumanoidRootPart")
	if not TargetHRP then
		Debounce = false
		return
	end

	PerformAnimation(PlayerHRP, PlayerHumanoid, TargetHRP)
end)
