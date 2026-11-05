-- main.lua  (runs the UI module and the finder module)
-- ASCII only, conservative syntax.
--
-- GitHub layout (all three files in the same folder of your repo):
--   main.lua     <- this file
--   ui.lua       <- the Y1 window
--   finder.lua   <- the server system
--
-- What you execute:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/main.lua"))()
--
-- Change BASE below to the same folder URL (it must end with a slash).

local BASE = "https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/"
local NO_CACHE = true     -- adds ?v=<time> so GitHub's cache never serves an old copy
local LOCAL_DIR = nil     -- for testing: set to a workspace folder (like "y1/") to read the files with readfile instead

---------------------------------------------------------------------
-- stop an older copy that is still running
---------------------------------------------------------------------
local okEnv, genv = pcall(function()
	return getgenv()
end)
if okEnv and genv and genv.__PF_STOP then
	pcall(genv.__PF_STOP)
end

---------------------------------------------------------------------
-- module loader
---------------------------------------------------------------------
local function fetch(name)
	if LOCAL_DIR then
		return readfile(LOCAL_DIR .. name)
	end
	local url = BASE .. name
	if NO_CACHE then
		url = url .. "?v=" .. tostring(os.time())
	end
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and body ~= "" then
		return body
	end
	-- fallback to the executor's request function
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if req then
		local ok2, res = pcall(function()
			return req({ Url = url, Method = "GET" })
		end)
		if ok2 and res and res.StatusCode == 200 and res.Body then
			return res.Body
		end
	end
	error("[Y1] could not download " .. name .. " (" .. url .. ")")
end

local function loadModule(name)
	local src = fetch(name)
	local fn, err = loadstring(src, "=" .. name)
	if not fn then
		error("[Y1] could not compile " .. name .. ": " .. tostring(err))
	end
	return fn()
end

---------------------------------------------------------------------
-- run both modules
---------------------------------------------------------------------
local UI = loadModule("ui.lua")
local Finder = loadModule("finder.lua")

local win = UI.new({
	Name = "Y1PlayerFinder",
	Logo = "Y1",
	MainTitle = "Player Finder",
	MainTip = "Player Finder",
})

local finder = nil
local okF, errF = pcall(function()
	finder = Finder.new(win, {
		RefreshEvery = 2,
		PageSize = 40,
		MaxPlayerRows = 100,
		GroupMemberCap = 5000,
	})
end)
if not okF then
	warn("[Y1] finder failed to start: " .. tostring(errF))
	win:Toast("Finder failed - see console (F9)")
end

-- lets the next run of this script stop this copy
local function stopAll()
	win:Unload()
end
if okEnv and genv then
	genv.__PF_STOP = stopAll
	win:OnUnload(function()
		if genv.__PF_STOP == stopAll then
			genv.__PF_STOP = nil
		end
	end)
end

return { UI = win, Finder = finder }
