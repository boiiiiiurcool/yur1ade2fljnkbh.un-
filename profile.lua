


-- profile.lua  (small player card: avatar, account age, copy profile link)
-- ASCII only, conservative syntax (no += and no continue).
--
--   local Profile = <this file>
--   local card = Profile.new(win, { http = httpJson, copy = copyText })
--   card:Open(userId, { name = "username", display = "Display Name" })   -- info is optional
--   card:Close()
--
-- deps.http(method, url) -> decoded json or nil   (used to read the account creation date)
-- deps.copy(text, message)                        (copies to the clipboard and shows a toast)

local Profile = {}

function Profile.new(win, deps)
	deps = deps or {}

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")

	local T = win.T
	local H = win.H
	local new = H.new
	local corner = H.corner
	local stroke = H.stroke
	local label = H.label

	local BORDER = T.BORDER
	local SIDEBAR_BG = T.SIDEBAR_BG
	local CARD_BG = T.CARD_BG
	local CLUSTER_BG = T.CLUSTER_BG
	local ICON = T.ICON
	local ICON_HOVER = T.ICON_HOVER
	local HOVER_GREY = T.HOVER_GREY
	local TEXT_COLOR = T.TEXT_COLOR
	local DIM_TEXT = T.DIM_TEXT
	local RADIUS = T.RADIUS
	local FAST = T.FAST

	local self = {}
	local token = 0
	local isOpen = false
	local currentId = nil
	local currentName = nil

	-- zIndex 21 sits above the window but under toasts (22), so copy toasts stay readable
	local overlay = new("CanvasGroup", {
		Name = "ProfileOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 21,
	}, win.Window)
	corner(overlay, RADIUS)

	local catcher = new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, overlay)

	local card = new("Frame", {
		Name = "ProfileCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(280, 224),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, overlay)
	corner(card, RADIUS + 4)
	stroke(card, BORDER, 1, 0)
	local cardScale = new("UIScale", { Scale = 0.9 }, card)

	local avatar = new("ImageLabel", {
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		Image = "",
	}, card)
	corner(avatar, 16)

	local displayLabel = label(card, "", UDim2.fromOffset(94, 24), UDim2.fromOffset(168, 20),
		Enum.Font.GothamMedium, 15, TEXT_COLOR)
	local userLabel = label(card, "", UDim2.fromOffset(94, 47), UDim2.fromOffset(168, 16),
		Enum.Font.Gotham, 12, DIM_TEXT)

	local function miniCard(x, title)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, 94),
			Size = UDim2.fromOffset(116, 44),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
		}, card)
		corner(f, RADIUS + 2)
		label(f, title, UDim2.fromOffset(12, 6), UDim2.fromOffset(92, 12), Enum.Font.Gotham, 11, DIM_TEXT)
		return label(f, "", UDim2.fromOffset(12, 21), UDim2.fromOffset(94, 18), Enum.Font.GothamMedium, 13, TEXT_COLOR)
	end
	local idValue = miniCard(18, "User ID")
	local ageValue = miniCard(146, "Account age")

	local createdLabel = label(card, "", UDim2.fromOffset(18, 146), UDim2.fromOffset(244, 14),
		Enum.Font.Gotham, 11, DIM_TEXT)

	local tray = new("Frame", {
		Position = UDim2.fromOffset(18, 172),
		Size = UDim2.fromOffset(244, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
	}, card)
	corner(tray, RADIUS + 2)

	local function trayButton(text, x)
		local b = new("TextButton", {
			AutoButtonColor = false,
			Text = text,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
			TextColor3 = ICON,
			Position = UDim2.fromOffset(x, 3),
			Size = UDim2.fromOffset(117, 24),
			BackgroundColor3 = HOVER_GREY,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, tray)
		corner(b, RADIUS)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundTransparency = 0, TextColor3 = ICON_HOVER }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundTransparency = 1, TextColor3 = ICON }):Play()
		end)
		return b
	end
	local linkBtn = trayButton("Copy profile link", 3)
	local nameBtn = trayButton("Copy username", 124)

	local function flash(btn, base)
		btn.Text = "Copied!"
		task.delay(1.2, function()
			if btn.Parent then
				btn.Text = base
			end
		end)
	end

	linkBtn.Activated:Connect(function()
		if currentId and deps.copy then
			deps.copy("https://www.roblox.com/users/" .. tostring(currentId) .. "/profile", "Profile link copied")
			flash(linkBtn, "Copy profile link")
		end
	end)
	nameBtn.Activated:Connect(function()
		if currentName and deps.copy then
			deps.copy(currentName, "Copied username: " .. currentName)
			flash(nameBtn, "Copy username")
		end
	end)

	---------------------------------------------------------------------
	-- account age
	---------------------------------------------------------------------
	local function formatAge(days)
		if days < 31 then
			return days .. " days"
		end
		local years = math.floor(days / 365)
		local months = math.floor((days % 365) / 30)
		if years > 0 then
			if months > 0 then
				return years .. "y " .. months .. "mo"
			end
			return years .. "y"
		end
		return months .. " mo"
	end

	local function showDays(days, createdText)
		ageValue.Text = formatAge(days)
		createdLabel.Text = "Created " .. createdText .. "  (" .. days .. " days old)"
	end

	---------------------------------------------------------------------
	-- open / close
	---------------------------------------------------------------------
	local IN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local OUT_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	function self:Open(userId, info)
		info = info or {}
		token = token + 1
		local t = token
		currentId = userId
		currentName = info.name

		displayLabel.Text = info.display or ("User " .. tostring(userId))
		if info.name then
			userLabel.Text = "@" .. info.name
		else
			userLabel.Text = "ID " .. tostring(userId)
		end
		idValue.Text = tostring(userId)
		avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
		ageValue.Text = "..."
		createdLabel.Text = "Loading account info..."

		-- instant answer when the player is in your own server
		local p = Players:GetPlayerByUserId(userId)
		if p then
			local days = p.AccountAge
			showDays(days, os.date("%Y-%m-%d", os.time() - days * 86400))
		end

		-- the exact creation date comes from the web api
		if deps.http then
			task.spawn(function()
				local data = deps.http("GET", "https://users.roblox.com/v1/users/" .. tostring(userId))
				if t ~= token then
					return
				end
				if data then
					if not currentName and data.name then
						currentName = data.name
						userLabel.Text = "@" .. data.name
					end
					if info.display == nil and data.displayName then
						displayLabel.Text = data.displayName
					end
					if data.created then
						local y, mo, d = string.match(tostring(data.created), "(%d+)-(%d+)-(%d+)")
						if y then
							local ts = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
							local days = math.max(0, math.floor((os.time() - ts) / 86400))
							showDays(days, y .. "-" .. mo .. "-" .. d)
							return
						end
					end
				end
				if ageValue.Text == "..." then
					ageValue.Text = "Unknown"
					createdLabel.Text = "Could not load account info"
				end
			end)
		elseif not p then
			ageValue.Text = "Unknown"
			createdLabel.Text = "Needs an executor request function"
		end

		linkBtn.Text = "Copy profile link"
		nameBtn.Text = "Copy username"

		if not isOpen then
			isOpen = true
			cardScale.Scale = 0.9
			overlay.GroupTransparency = 1
			overlay.Visible = true
			TweenService:Create(overlay, FAST, { GroupTransparency = 0 }):Play()
			TweenService:Create(cardScale, IN_INFO, { Scale = 1 }):Play()
		end
	end

	function self:Close()
		if not isOpen then
			return
		end
		isOpen = false
		token = token + 1
		local t = token
		TweenService:Create(overlay, OUT_INFO, { GroupTransparency = 1 }):Play()
		TweenService:Create(cardScale, OUT_INFO, { Scale = 0.92 }):Play()
		task.delay(OUT_INFO.Time + 0.02, function()
			if t == token and not isOpen then
				overlay.Visible = false
			end
		end)
	end

	catcher.Activated:Connect(function()
		self:Close()
	end)

	return self
end

return Profile
