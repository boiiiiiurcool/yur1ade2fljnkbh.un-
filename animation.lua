-- animation.lua  (Y1 Misc tab > Extra page: Animations card, built INTO extra.lua's page)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Detects the Idle / Walk / Run / Jump / Fall / Swim / Climb animations your character has right now
-- (from its Animate script) and remembers them as "Default". The three dots open a pop-up with
-- one drop-down per animation: Default or any animation package.
-- It changes the AnimationId values inside your Animate script and restarts that script, so the
-- animations are played by your own client and Roblox shows them to every other player.
-- Packages are R15 only. Turning the switch off (or unloading) puts your defaults back.
--
-- Build signature: Animation.build(container, T, H, ctx) -> { Unload = fn }
-- ctx.Helpers is handed over by extra.lua (switch, dots, floating pop-up, drop-down, placement).

local AnimationPage = {}

function AnimationPage.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local RADIUS = T.RADIUS

	local X = nil
	if type(ctx) == "table" then
		X = ctx.Helpers
	end
	if type(X) ~= "table" then
		warn("[animation] extra.lua did not pass its helpers")
		return { Unload = function() end }
	end

	-- asset ids from the official Roblox animation bundle table
	-- (idle1 / idle2 = the two idle animations the Animate script switches between)
	local PACKS = {
		{ name = "Rthro", idle1 = "2510197257", idle2 = "2510196951", walk = "2510202577", run = "2510198475", jump = "2510197830", fall = "2510195892", climb = "2510192778", swim = "2510199791", swimidle = "2510201162" },
		{ name = "Mage", idle1 = "707742142", idle2 = "707855907", walk = "707897309", run = "707861613", jump = "707853694", fall = "707829716", climb = "707826056", swim = "707876443", swimidle = "707894699" },
		{ name = "Zombie", idle1 = "616158929", idle2 = "616160636", walk = "616168032", run = "616163682", jump = "616161997", fall = "616157476", climb = "616156119", swim = "616165109", swimidle = "616166655" },
		{ name = "Elder", idle1 = "845397899", idle2 = "845400520", walk = "845403856", run = "845386501", jump = "845398858", fall = "845396048", climb = "845392038", swim = "845401742", swimidle = "845403127" },
		{ name = "Ninja", idle1 = "656117400", idle2 = "656118341", walk = "656121766", run = "656118852", jump = "656117878", fall = "656115606", climb = "656114359", swim = "656119721", swimidle = "656121397" },
		{ name = "Vampire", idle1 = "1083445855", idle2 = "1083450166", walk = "1083473930", run = "1083462077", jump = "1083455352", fall = "1083443587", climb = "1083439238", swim = "1083464683", swimidle = "1083467779" },
		{ name = "Werewolf", idle1 = "1083195517", idle2 = "1083214717", walk = "1083178339", run = "1083216690", jump = "1083218792", fall = "1083189019", climb = "1083182000", swim = "1083222527", swimidle = "1083225406" },
		{ name = "Levitation", idle1 = "616006778", idle2 = "616008087", walk = "616013216", run = "616010382", jump = "616008936", fall = "616005863", climb = "616003713", swim = "616011509", swimidle = "616012453" },
		{ name = "Astronaut", idle1 = "891621366", idle2 = "891633237", walk = "891636393", run = "891636393", jump = "891627522", fall = "891617961", climb = "891609353", swim = "891639666", swimidle = "891663592" },
		{ name = "Knight", idle1 = "657595757", idle2 = "657568135", walk = "657552124", run = "657564596", jump = "658409194", fall = "657600338", climb = "658360781", swim = "657560551", swimidle = "657557095" },
		{ name = "Pirate", idle1 = "750781874", idle2 = "750782770", walk = "750785693", run = "750783738", jump = "750782230", fall = "750780242", climb = "750779899", swim = "750784579", swimidle = "750785176" },
	}
	local NAMES = { "Default" }
	for i = 1, #PACKS do
		NAMES[i + 1] = PACKS[i].name
	end

	-- the drop-downs, top to bottom (key = which selection it controls)
	local ROWS = {
		{ key = "idle", title = "Idle" },
		{ key = "walk", title = "Walk" },
		{ key = "run", title = "Run" },
		{ key = "jump", title = "Jump" },
		{ key = "fall", title = "Fall" },
		{ key = "swim", title = "Swim" },
		{ key = "climb", title = "Climb" },
	}

	-- used to recognise which pack your default set is (idle is left out, it varies per game)
	local DETECT = { "walk", "run", "jump", "fall", "swim", "climb" }

	-- every value inside the Animate script that gets changed
	-- (Idle changes both idle animations, Swim also changes the swim idle)
	local TARGETS = {
		{ field = "idle1", sel = "idle", folder = "idle", anim = "Animation1", exact = true },
		{ field = "idle2", sel = "idle", folder = "idle", anim = "Animation2", exact = true },
		{ field = "walk", sel = "walk", folder = "walk", anim = "WalkAnim" },
		{ field = "run", sel = "run", folder = "run", anim = "RunAnim" },
		{ field = "jump", sel = "jump", folder = "jump", anim = "JumpAnim" },
		{ field = "fall", sel = "fall", folder = "fall", anim = "FallAnim" },
		{ field = "climb", sel = "climb", folder = "climb", anim = "ClimbAnim" },
		{ field = "swim", sel = "swim", folder = "swim", anim = "Swim" },
		{ field = "swimidle", sel = "swim", folder = "swimidle", anim = "SwimIdle" },
	}

	local running = true
	local enabled = false
	local sel = { idle = 1, walk = 1, run = 1, jump = 1, fall = 1, swim = 1, climb = 1 }   -- 1 = Default
	local defaults = {}
	local hasDefaults = false
	local detected = "Game default"
	local conns = {}
	local applyToken = 0
	local statusLbl = nil
	local schedule = nil

	local function num(id)
		return string.match(tostring(id or ""), "(%d+)%s*$")
	end

	local function findAnim(animate, folderName, animName, exact)
		local f = animate:FindFirstChild(folderName)
		if not f then
			return nil
		end
		local a = f:FindFirstChild(animName)
		if a and a:IsA("Animation") then
			return a
		end
		if exact then
			return nil
		end
		local kids = f:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("Animation") then
				return kids[i]
			end
		end
		return nil
	end

	---------------------------------------------------------------------
	-- card (right half, second row of the Extra page) + settings pop-up
	---------------------------------------------------------------------
	local card = new("Frame", {
		Name = "AnimationsCard",
		Position = UDim2.new(0.5, 4, 0, 98),
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, parent)
	corner(card, RADIUS + 4)
	stroke(card, T.BORDER, 1, 0)

	local caption = label(parent, "ANIMATIONS", UDim2.new(0.5, 6, 0, 80), UDim2.new(0.5, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	label(card, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local sub = label(card, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	sub.RichText = true

	local function refreshSub()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		sub.Text = state
	end
	refreshSub()

	X.makeSwitch(card, false, function(on)
		enabled = on
		refreshSub()
		schedule()
	end, 23)

	local dots = X.makeDots(card, UDim2.new(1, -58, 0, 23))

	local PW = 300
	local PH = 328
	local F = X.makeFloating("AnimationSettings", PW, PH)
	local pop = F.frame

	label(pop, "Animations", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)
	statusLbl = label(pop, "", UDim2.fromOffset(16, 46), UDim2.new(1, -32, 0, 16),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	local dropdowns = {}
	for i = 1, #ROWS do
		local row = ROWS[i]
		dropdowns[#dropdowns + 1] = X.dropdownRow(pop, 68 + (i - 1) * 36, row.title, 120, 128, NAMES, 1,
			function(idx)
				sel[row.key] = idx
				schedule()
			end, pop)
	end

	local function openAnim()
		if F.isOpen() then
			return
		end
		F.open(X.placeNear(dots.btn, PW, PH, nil))
		dots.open = true
		dots.paint()
	end

	local function closeAnim()
		F.close()
		for i = 1, #dropdowns do
			dropdowns[i].close()
		end
		dots.open = false
		dots.paint()
	end

	dots.btn.Activated:Connect(function()
		if F.isOpen() then
			closeAnim()
		else
			openAnim()
		end
	end)

	local hit = { pop, dots.btn }
	for i = 1, #dropdowns do
		hit[#hit + 1] = dropdowns[i].frame
	end
	X.addPopup({
		isOpen = function()
			return F.isOpen()
		end,
		close = closeAnim,
		hit = hit,
	})

	---------------------------------------------------------------------
	-- detecting + applying
	---------------------------------------------------------------------
	local function refreshStatus()
		if not statusLbl or not statusLbl.Parent then
			return
		end
		local char = player.Character
		local hum = nil
		if char then
			hum = char:FindFirstChildOfClass("Humanoid")
		end
		if not char or not char:FindFirstChild("Animate") then
			statusLbl.Text = "No Animate script found yet"
		elseif hum and hum.RigType == Enum.HumanoidRigType.R6 then
			statusLbl.Text = "R6 rig - packages need R15"
		else
			statusLbl.Text = "Your default set: " .. detected
		end
	end

	local function capture(animate)
		defaults = {}
		for i = 1, #TARGETS do
			local t = TARGETS[i]
			local a = findAnim(animate, t.folder, t.anim, t.exact)
			if a then
				defaults[t.field] = a.AnimationId
			end
		end
		hasDefaults = true

		detected = "Game default"
		for p = 1, #PACKS do
			local all = true
			for r = 1, #DETECT do
				local f = DETECT[r]
				if num(defaults[f]) ~= PACKS[p][f] then
					all = false
				end
			end
			if all then
				detected = PACKS[p].name
			end
		end
		refreshStatus()
	end

	-- the Animate script only reads its ids when it starts, so it is switched off and on again
	local function restart(char, animate, old)
		task.spawn(function()
			local hum = char:FindFirstChildOfClass("Humanoid")
			local animator = nil
			if hum then
				animator = hum:FindFirstChildOfClass("Animator")
			end
			pcall(function()
				animate.Disabled = true
			end)
			if animator then
				local ok, tracks = pcall(function()
					return animator:GetPlayingAnimationTracks()
				end)
				if ok and tracks then
					for i = 1, #tracks do
						local a = tracks[i].Animation
						local n = nil
						if a then
							n = num(a.AnimationId)
						end
						if n and old[n] then
							pcall(function()
								tracks[i]:Stop(0)
							end)
						end
					end
				end
			end
			task.wait()
			pcall(function()
				animate.Disabled = false
			end)
		end)
	end

	local function apply()
		local char = player.Character
		local animate = nil
		if char then
			animate = char:FindFirstChild("Animate")
		end
		if not animate or not hasDefaults then
			return
		end
		local old = {}
		local changed = false
		for i = 1, #TARGETS do
			local t = TARGETS[i]
			local a = findAnim(animate, t.folder, t.anim, t.exact)
			local base = defaults[t.field]
			if a and base then
				local want = base
				if enabled then
					local idx = sel[t.sel]
					if idx > 1 then
						want = "rbxassetid://" .. PACKS[idx - 1][t.field]
					end
				end
				if a.AnimationId ~= want then
					local n = num(a.AnimationId)
					if n then
						old[n] = true
					end
					a.AnimationId = want
					changed = true
				end
			end
		end
		if changed then
			restart(char, animate, old)
		end
	end

	-- several quick clicks become one restart
	schedule = function()
		applyToken = applyToken + 1
		local tk = applyToken
		task.delay(0.15, function()
			if tk == applyToken and running then
				apply()
			end
		end)
	end

	-- every respawn resets the Animate script, so the defaults are read again and the picks re-applied
	local function onCharacter(char)
		hasDefaults = false
		defaults = {}
		task.spawn(function()
			local animate = char:WaitForChild("Animate", 10)
			if not running or not animate then
				refreshStatus()
				return
			end
			task.wait(0.6)
			if not running or player.Character ~= char then
				return
			end
			capture(animate)
			if enabled then
				apply()
			end
		end)
	end

	conns[#conns + 1] = player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	refreshStatus()

	---------------------------------------------------------------------
	-- unload: put the original animations back
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		enabled = false
		pcall(apply)
		running = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			card:Destroy()
			caption:Destroy()
		end)
	end

	return { Unload = unload }
end

return AnimationPage
