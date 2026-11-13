-- hitboxspoofer.lua  (used by the Hitbox Expander in animation.lua)
-- ASCII only, conservative syntax (no += and no continue). No console output on purpose.
--
-- When it is switched on it does two things for EVERY player (the blood fix is for other players, the armor fix for everybody):
--
--   1) BLOOD (bloodpoint v2): blood comes out at its usual place on the body part that was hit, even though the
--      HumanoidRootPart is a big hitbox. Blood on the big hitbox is moved onto the closest real body part first.
--      :Emit() is hooked so the blood is moved BEFORE the particles are born; loose blood from your own shots is caught;
--      a safety sweep catches blood that already exists.
--
--   2) ARMOR (armorlock): the armor visual (DefenseBBGUI + Vest) keeps its normal size and position no matter how big the
--      hitbox is. DefenseBBGUI.ExtentsOffset is counted in multiples of the part size, so it is set to 0 and a fixed offset
--      in studs is used instead.
--
-- When it is switched off everything is put back: armor values are restored, blood emitters go back to where the game put
-- them and the helper attachments are removed.
--
-- Use:
--   local spoofer = HitboxSpoofer.new()
--   spoofer:SetEnabled(true)    -- on
--   spoofer:SetEnabled(false)   -- off (everything restored)
--   spoofer:IsEnabled()
--   spoofer:Unload()            -- off + can not be used again

local HitboxSpoofer = {}

function HitboxSpoofer.new(options)
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer

	---------------------------------------------------------------------
	-- settings
	---------------------------------------------------------------------
	local KEEP_TIME = 3        -- seconds before a moved temporary emitter is removed
	local SHOT_WINDOW = 0.75   -- seconds after a click that loose blood counts as yours
	local MAX_DIST = 15        -- loose blood: victim must be this close

	-- usual blood point for each body part, in that part's own space
	local USUAL = {
		Head = Vector3.new(0.40, 0.58, 0.00),
		UpperTorso = Vector3.new(1.63, 0.04, 1.46),
		LowerTorso = Vector3.new(0.26, 0.20, 0.26),
		LeftUpperArm = Vector3.new(-0.62, 0.70, -0.18),
		LeftLowerArm = Vector3.new(-0.58, 0.21, -0.21),
		LeftHand = Vector3.new(0.00, -1.54, 0.74),
		RightUpperArm = Vector3.new(1.29, 0.83, -0.14),
		RightLowerArm = Vector3.new(0.29, -0.13, -1.28),
		RightHand = Vector3.new(0.00, -0.41, -0.23),
		LeftUpperLeg = Vector3.new(-0.08, -0.45, -1.98),
		LeftLowerLeg = Vector3.new(-0.19, 0.25, -1.02),
		LeftFoot = Vector3.new(0.00, 0.00, 0.00),
		RightUpperLeg = Vector3.new(0.46, 0.16, 0.23),
		RightLowerLeg = Vector3.new(0.06, -0.30, 2.20),
		RightFoot = Vector3.new(1.44, -3.38, -0.25),
	}

	-- armor visual: the normal values (measured with the hitbox expander off)
	local BB_SIZE = UDim2.new(8, 0, 8, 0)          -- DefenseBBGUI.Size
	local VEST_SIZE = UDim2.new(0.5, 0, 0.5, 0)    -- Vest.Size
	local VEST_POS = UDim2.new(0.5, 0, 0.5, 0)     -- Vest.Position
	local POSITION = Vector3.new(0, 0, 0.5)        -- studs from the root part (camera space: x right, y up, z toward camera)
	local SIZE_OFFSET = Vector2.new(0, 0)          -- DefenseBBGUI.SizeOffset
	local ZERO = Vector3.new(0, 0, 0)

	---------------------------------------------------------------------
	-- state
	---------------------------------------------------------------------
	local unloaded = false
	local active = false
	local token = 0
	local conns = {}
	local hookInstalled = false

	local function live()
		return active and not unloaded
	end

	---------------------------------------------------------------------
	-- caches (so the namecall hook never has to call Instance methods)
	---------------------------------------------------------------------
	local modelOwner = {}     -- [character model] = player
	local playerByName = {}   -- [name] = player
	local charParts = {}      -- [character model] = { [part name] = part }
	local anchors = {}        -- [player] = { [part name] = Attachment at the usual point }

	local function cacheParts(model)
		local map = {}
		for _, c in ipairs(model:GetChildren()) do
			if c:IsA("BasePart") then
				map[c.Name] = c
			end
		end
		charParts[model] = map
	end

	local function refreshPlayers()
		for _, p in ipairs(Players:GetPlayers()) do
			playerByName[p.Name] = p
			if p.Character then
				modelOwner[p.Character] = p
				cacheParts(p.Character)
			end
		end
	end

	-- one anchor per body part, sitting at that part's usual blood point
	local function ensureAnchor(plr, partName)
		local char = plr.Character
		local parts = char and charParts[char]
		local part = parts and parts[partName]
		if not part or not part.Parent then
			return nil
		end
		local byPart = anchors[plr]
		if not byPart then
			byPart = {}
			anchors[plr] = byPart
		end
		local a = byPart[partName]
		if a and a.Parent == part then
			return a
		end
		a = Instance.new("Attachment")
		a.Name = "BloodPointAnchor"
		a.Position = USUAL[partName]
		a.Parent = part
		byPart[partName] = a
		return a
	end

	local function ensureAllAnchors(plr)
		for name, _ in pairs(USUAL) do
			ensureAnchor(plr, name)
		end
	end

	-- who owns this instance? (index-only, safe inside the namecall hook)
	local function ownerOf(inst)
		local node = inst
		local n = 0
		while node and n < 14 do
			if node.ClassName == "Model" then
				local plr = modelOwner[node] or playerByName[node.Name]
				if plr then
					return plr
				end
			end
			node = node.Parent
			n = n + 1
		end
		return nil
	end

	local function bloodish(o)
		if string.find(string.lower(o.Name), "blood", 1, true) then
			return true
		end
		local p = o.Parent
		if p and string.find(string.lower(p.Name), "blood", 1, true) then
			return true
		end
		return false
	end

	-- which real body part is closest to a point on the big hitbox part? (pos is local to that part)
	local function pickPart(pos, size)
		local nx = pos.X / math.max(size.X / 2, 0.01)
		local ny = pos.Y / math.max(size.Y / 2, 0.01)
		if ny >= 0.55 then
			return "Head"
		end
		if math.abs(nx) >= 0.6 and ny >= -0.25 then
			if nx > 0 then
				return "RightUpperArm"
			end
			return "LeftUpperArm"
		end
		if ny >= 0.1 then
			return "UpperTorso"
		end
		if ny >= -0.3 then
			return "LowerTorso"
		end
		if nx > 0 then
			return "RightUpperLeg"
		end
		return "LeftUpperLeg"
	end

	-- the body part name an emitter belongs to (hook-safe: property reads only)
	local function partNameOf(em)
		local spot = em.Parent
		if not spot then
			return nil
		end
		local part = spot
		if spot.ClassName == "Attachment" then
			part = spot.Parent
		end
		if not part then
			return nil
		end
		local name = part.Name
		if name == "BloodPointAnchor" then
			return nil
		end
		if USUAL[name] then
			return name
		end
		if name == "HumanoidRootPart" and spot.ClassName == "Attachment" then
			return pickPart(spot.Position, part.Size)
		end
		return nil
	end

	---------------------------------------------------------------------
	-- BLOOD: pinning (hook-safe: only property reads/writes, no method calls)
	---------------------------------------------------------------------
	local lastShot = -math.huge
	local pinned = {}     -- [emitter] = { player, part name, original parent, temporary }
	local tempQueue = {}  -- { emitter, expireTime }

	local function pinEmitter(em, plr, partName, temporary)
		local byPart = anchors[plr]
		local a = byPart and byPart[partName]
		if not a or not a.Parent then
			return false
		end
		local orig = em.Parent
		if em.Parent ~= a then
			em.Parent = a
		end
		if not pinned[em] then
			pinned[em] = { plr, partName, orig, temporary and true or false }
			if temporary then
				tempQueue[#tempQueue + 1] = { em, os.clock() + KEEP_TIME }
			end
		end
		return true
	end

	local function nearestOther(pos)
		local best, bestDist = nil, MAX_DIST
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then
				local root = p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Head")
				if root then
					local d = (root.Position - pos).Magnitude
					if d < bestDist then
						best, bestDist = p, d
					end
				end
			end
		end
		return best
	end

	-- closest real body part of a player to a world position
	local function nearestPartName(plr, pos)
		local parts = plr.Character and charParts[plr.Character]
		if not parts then
			return nil
		end
		local bestName, bestDist = nil, math.huge
		for name, _ in pairs(USUAL) do
			local part = parts[name]
			if part and part.Parent then
				local d = (part.Position - pos).Magnitude
				if d < bestDist then
					bestName, bestDist = name, d
				end
			end
		end
		return bestName
	end

	local function handleEmitter(em, temporary)
		local owner = ownerOf(em)
		if owner then
			if owner ~= LocalPlayer then
				ensureAllAnchors(owner)
				local partName = partNameOf(em)
				if not partName then
					-- unknown part (or already moved): fall back to the head
					partName = "Head"
				end
				pinEmitter(em, owner, partName, temporary)
			end
		else
			-- loose in the world: only if it came from your shot
			if os.clock() - lastShot > SHOT_WINDOW then
				return
			end
			local pos = nil
			pcall(function()
				local p = em.Parent
				if p:IsA("Attachment") then
					pos = p.WorldPosition
				else
					pos = p.Position
				end
			end)
			local victim = pos and nearestOther(pos)
			if victim then
				ensureAllAnchors(victim)
				local partName = nearestPartName(victim, pos) or "Head"
				pinEmitter(em, victim, partName, true)
			end
		end
	end

	-- safety sweep: catches blood that already existed
	local function sweep()
		refreshPlayers()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then
				ensureAllAnchors(p)
				for _, d in ipairs(p.Character:GetDescendants()) do
					if d.ClassName == "ParticleEmitter" and bloodish(d)
						and not (d.Parent and d.Parent.Name == "BloodPointAnchor") then
						handleEmitter(d, false)
					end
				end
			end
		end
	end

	local function hookChar(p, c)
		modelOwner[c] = p
		task.delay(0.5, function()
			if live() and c.Parent then
				pcall(cacheParts, c)
			end
		end)
	end

	-- puts every moved emitter back where the game had it, and removes the helper attachments
	local function restoreBlood()
		for em, info in pairs(pinned) do
			if em.Parent then
				if info[4] then
					pcall(function()
						em:Destroy()
					end)
				elseif info[3] and info[3].Parent then
					pcall(function()
						em.Parent = info[3]
					end)
				end
			end
		end
		pinned = {}
		tempQueue = {}
		for _, byPart in pairs(anchors) do
			for _, a in pairs(byPart) do
				pcall(function()
					a:Destroy()
				end)
			end
		end
		anchors = {}
		modelOwner = {}
		playerByName = {}
		charParts = {}
	end

	---------------------------------------------------------------------
	-- ARMOR: keep the visual at its normal size and position
	---------------------------------------------------------------------
	local armorOrig = {}     -- [billboard] = the values the game had
	local armorHooked = {}   -- [billboard] = true
	local applying = false   -- guard: our own writes must not call us again

	local function saveOrig(bb)
		if armorOrig[bb] then
			return
		end
		local vest = bb:FindFirstChild("Vest")
		armorOrig[bb] = {
			size = bb.Size,
			studs = bb.StudsOffset,
			studsWS = bb.StudsOffsetWorldSpace,
			ext = bb.ExtentsOffset,
			extWS = bb.ExtentsOffsetWorldSpace,
			sizeOff = bb.SizeOffset,
			vest = vest,
			vestSize = vest and vest.Size,
			vestPos = vest and vest.Position,
		}
	end

	local function restoreArmor()
		for bb, o in pairs(armorOrig) do
			if bb.Parent then
				pcall(function()
					bb.Size = o.size
					bb.StudsOffset = o.studs
					bb.StudsOffsetWorldSpace = o.studsWS
					bb.ExtentsOffset = o.ext
					bb.ExtentsOffsetWorldSpace = o.extWS
					bb.SizeOffset = o.sizeOff
					if o.vest and o.vest.Parent then
						o.vest.Size = o.vestSize
						o.vest.Position = o.vestPos
					end
				end)
			end
		end
		armorOrig = {}
		armorHooked = {}
	end

	-- only writes when something is different
	local function applyArmor(bb, vest)
		if bb.Size ~= BB_SIZE then
			bb.Size = BB_SIZE
		end
		if bb.StudsOffset ~= POSITION then
			bb.StudsOffset = POSITION
		end
		if bb.StudsOffsetWorldSpace ~= ZERO then
			bb.StudsOffsetWorldSpace = ZERO
		end
		if bb.ExtentsOffset ~= ZERO then
			bb.ExtentsOffset = ZERO
		end
		if bb.ExtentsOffsetWorldSpace ~= ZERO then
			bb.ExtentsOffsetWorldSpace = ZERO
		end
		if bb.SizeOffset ~= SIZE_OFFSET then
			bb.SizeOffset = SIZE_OFFSET
		end
		if vest then
			if vest.Size ~= VEST_SIZE then
				vest.Size = VEST_SIZE
			end
			if vest.Position ~= VEST_POS then
				vest.Position = VEST_POS
			end
		end
	end

	local function guardedArmor(bb, vest)
		if applying then
			return
		end
		applying = true
		pcall(applyArmor, bb, vest)
		applying = false
	end

	-- snap back the instant the game changes any of it
	local function hookArmor(bb)
		if armorHooked[bb] then
			return
		end
		armorHooked[bb] = true
		saveOrig(bb)
		local function snap()
			if live() then
				guardedArmor(bb, bb:FindFirstChild("Vest"))
			end
		end
		for _, prop in ipairs({ "Size", "StudsOffset", "StudsOffsetWorldSpace", "ExtentsOffset",
			"ExtentsOffsetWorldSpace", "SizeOffset" }) do
			conns[#conns + 1] = bb:GetPropertyChangedSignal(prop):Connect(snap)
		end
		local vest = bb:FindFirstChild("Vest")
		if vest then
			conns[#conns + 1] = vest:GetPropertyChangedSignal("Size"):Connect(snap)
			conns[#conns + 1] = vest:GetPropertyChangedSignal("Position"):Connect(snap)
		end
	end

	---------------------------------------------------------------------
	-- namecall hook: moves blood on :Emit() BEFORE the particles are born
	-- (installed once; it does nothing while the spoofer is off)
	---------------------------------------------------------------------
	local function installNamecall()
		if hookInstalled then
			return
		end
		hookInstalled = true
		local canHook = (type(hookmetamethod) == "function") and (type(newcclosure) == "function")
			and (type(getnamecallmethod) == "function")
		if not canHook then
			return
		end
		pcall(function()
			local old
			old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				local method = getnamecallmethod()
				if method == "Emit" and live() and typeof(self) == "Instance" then
					local ours = false
					if type(checkcaller) == "function" then
						ours = checkcaller()
					end
					if not ours then
						pcall(function()
							if self.ClassName == "ParticleEmitter" and bloodish(self) then
								local owner = ownerOf(self)
								if owner and owner ~= LocalPlayer then
									local partName = partNameOf(self)
									if partName then
										pinEmitter(self, owner, partName, false)
									end
								end
							end
						end)
						if type(setnamecallmethod) == "function" then
							pcall(setnamecallmethod, method)
						end
					end
				end
				return old(self, ...)
			end))
		end)
	end

	---------------------------------------------------------------------
	-- start / stop
	---------------------------------------------------------------------
	local function start()
		active = true
		token = token + 1
		local myToken = token
		refreshPlayers()

		-- track your shots
		conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
			if not live() then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				local char = LocalPlayer.Character
				if char and char:FindFirstChildWhichIsA("Tool") then
					lastShot = os.clock()
				end
			end
		end)

		-- keep pinned emitters in place, remove temporary ones
		conns[#conns + 1] = RunService.Heartbeat:Connect(function()
			if not live() then
				return
			end
			for em, info in pairs(pinned) do
				if not em.Parent then
					pinned[em] = nil
				else
					local byPart = anchors[info[1]]
					local a = byPart and byPart[info[2]]
					if a and a.Parent and em.Parent ~= a then
						em.Parent = a
					end
				end
			end
			local now = os.clock()
			for i = #tempQueue, 1, -1 do
				local item = tempQueue[i]
				if now >= item[2] then
					pcall(function()
						item[1]:Destroy()
					end)
					table.remove(tempQueue, i)
				end
			end
		end)

		-- new blood
		conns[#conns + 1] = workspace.DescendantAdded:Connect(function(o)
			if not live() then
				return
			end
			if o.ClassName == "ParticleEmitter" and bloodish(o) then
				handleEmitter(o, true)
			end
		end)

		-- player / character caches
		conns[#conns + 1] = Players.PlayerAdded:Connect(function(p)
			playerByName[p.Name] = p
			conns[#conns + 1] = p.CharacterAdded:Connect(function(c)
				hookChar(p, c)
			end)
		end)
		for _, p in ipairs(Players:GetPlayers()) do
			conns[#conns + 1] = p.CharacterAdded:Connect(function(c)
				hookChar(p, c)
			end)
		end

		-- armor visual of everybody, every frame before it is drawn
		conns[#conns + 1] = RunService.RenderStepped:Connect(function()
			if not live() then
				return
			end
			local folder = workspace:FindFirstChild("Players")
			if not folder then
				return
			end
			for _, char in ipairs(folder:GetChildren()) do
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local bb = hrp and hrp:FindFirstChild("DefenseBBGUI")
				if bb then
					hookArmor(bb)
					guardedArmor(bb, bb:FindFirstChild("Vest"))
				end
			end
		end)

		-- blood sweep + clean up entries of billboards that no longer exist
		task.spawn(function()
			while live() and token == myToken do
				pcall(sweep)
				for bb, _ in pairs(armorOrig) do
					if not bb.Parent then
						armorOrig[bb] = nil
						armorHooked[bb] = nil
					end
				end
				task.wait(0.5)
			end
		end)

		installNamecall()
	end

	local function stop()
		active = false
		token = token + 1
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		restoreArmor()
		restoreBlood()
	end

	---------------------------------------------------------------------
	-- public object
	---------------------------------------------------------------------
	local obj = {}

	function obj:SetEnabled(on)
		on = on and true or false
		if unloaded or on == active then
			return
		end
		if on then
			start()
		else
			stop()
		end
	end

	function obj:IsEnabled()
		return active
	end

	function obj:Unload()
		if unloaded then
			return
		end
		if active then
			stop()
		end
		unloaded = true
	end

	return obj
end

return HitboxSpoofer
