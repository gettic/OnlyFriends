-- Only Friends: declines party invites from players who are not your friends
-- (WoW or Battle.net) or in your guild.

local ADDON_NAME = ...
local PREFIX = "|cff33ff99Only Friends|r: "
local GUILD_WAIT = 3        -- seconds to wait for a late guild roster
local LINE_THROTTLE = 10    -- seconds between chat lines for the same inviter

local DEFAULTS = { dbVersion = 1, enabled = true }
local MINIMAP_DEFAULTS = { hide = false, angle = 225 } -- OnlyFriendsDB.minimap

-- The minimap button's art: Blizzard's own textures by name, all in one place.
local ART = {
	background   = "Interface\\Minimap\\UI-Minimap-Background",
	border       = "Interface\\Minimap\\MiniMap-TrackingBorder",
	highlight    = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
	icon         = "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon",
	iconFallback = "Interface\\Icons\\INV_Misc_GroupNeedMore",
	offMark      = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", -- red X shown while off
	offDim       = 0.6, -- icon brightness while off (it is also greyed out)
}

local frame = CreateFrame("Frame")
local pending       -- invite waiting for the guild roster: { name, guid, token }
local lastLine = {} -- inviter name -> time of last chat line

local function Print(msg)
	print(PREFIX .. msg)
end

-- Fill in missing settings; never resets what's already saved.
local function InitDB()
	if type(OnlyFriendsDB) ~= "table" then OnlyFriendsDB = {} end
	for k, v in pairs(DEFAULTS) do
		if OnlyFriendsDB[k] == nil then OnlyFriendsDB[k] = v end
	end
	-- Minimap button settings: repair a broken value, keep the rest.
	if type(OnlyFriendsDB.minimap) ~= "table" then OnlyFriendsDB.minimap = {} end
	local mm = OnlyFriendsDB.minimap
	if type(mm.hide) ~= "boolean" then mm.hide = MINIMAP_DEFAULTS.hide end
	if type(mm.angle) ~= "number" or mm.angle ~= mm.angle or mm.angle == math.huge or mm.angle == -math.huge then
		mm.angle = MINIMAP_DEFAULTS.angle
	end
end

local function IsEnabled()
	return not OnlyFriendsDB or OnlyFriendsDB.enabled ~= false
end

-- "Name" -> "Name-Realm" (own realm added when missing).
local function NormalizeName(name)
	if not name or name == "" then return nil end
	if name:find("-", 1, true) then return name end
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return result end
	return nil
end

local function GuildRosterMissing()
	return IsInGuild and IsInGuild() and (GetNumGuildMembers() or 0) == 0
end

-- true = friend/guild, false = not, nil = can't tell yet (guild roster not loaded).
local function IsTrusted(name, guid)
	local hasGuid = type(guid) == "string" and guid ~= ""
	local fullName = NormalizeName(name)

	if hasGuid then
		if SafeCall(C_BattleNet and C_BattleNet.GetAccountInfoByGUID, guid) then return true end
		if SafeCall(C_FriendList and C_FriendList.IsFriend, guid) then return true end
	end
	if name and name ~= "" and C_FriendList then
		if SafeCall(C_FriendList.GetFriendInfo, name) then return true end
		if fullName ~= name and SafeCall(C_FriendList.GetFriendInfo, fullName) then return true end
	end

	if GuildRosterMissing() then return nil end
	if hasGuid and SafeCall(IsGuildMember, guid) then return true end
	if name and name ~= "" and C_GuildInfo then
		if SafeCall(C_GuildInfo.MemberExistsByName, name) then return true end
		if fullName ~= name and SafeCall(C_GuildInfo.MemberExistsByName, fullName) then return true end
	end
	return false
end

local function InviteStillOpen()
	if StaticPopup_Visible and StaticPopup_Visible("PARTY_INVITE") then return true end
	if LFGInvitePopup and LFGInvitePopup:IsShown() then return true end
	return false
end

local function HidePopups()
	if StaticPopup_Visible and StaticPopup_Visible("PARTY_INVITE") then
		StaticPopup_Hide("PARTY_INVITE")
	end
	if LFGInvitePopup and LFGInvitePopup:IsShown() and StaticPopupSpecial_Hide then
		StaticPopupSpecial_Hide(LFGInvitePopup)
	end
end

-- Clickable name when possible; no realm shown for your own realm.
local function NameText(name)
	if not name or name == "" then return UNKNOWNOBJECT or "an unknown player" end
	local fullName = NormalizeName(name)
	local shown = Ambiguate and Ambiguate(fullName, "none") or name
	if type(GetPlayerLink) == "function" then
		local ok, link = pcall(GetPlayerLink, fullName, "[" .. shown .. "]")
		if ok and link then return link end
	end
	return shown
end

local function PrintThrottled(name, msg)
	local key = name or "?"
	local now = GetTime()
	if lastLine[key] and now - lastLine[key] < LINE_THROTTLE then return end
	lastLine[key] = now
	Print(msg)
end

local function DeclineInvite(name)
	DeclineGroup()
	HidePopups()
	-- Blizzard may show its popup after our handler runs: close it again next frame.
	C_Timer.After(0, HidePopups)
	PrintThrottled(name, "declined a party invite from " .. NameText(name) .. ".")
end

-- Not trusted: decline, or for Party Sync only print a note (its dialog is left alone).
local function Reject(name, questSessionActive)
	if questSessionActive then
		PrintThrottled(name, "Party Sync invite from " .. NameText(name) .. " (not a friend or guild member) - left for you to answer.")
	else
		DeclineInvite(name)
	end
end

-- Final decision on an invite that waited for the guild roster.
local function ResolvePending()
	local p = pending
	pending = nil
	if not p then return end
	if not p.questSessionActive and not InviteStillOpen() then return end -- already answered or cancelled
	if IsTrusted(p.name, p.guid) then return end
	Reject(p.name, p.questSessionActive)
end

-- Decide on an invite; may leave it pending for the guild roster.
local function HandleInvite(name, guid, questSessionActive)
	local trusted = IsTrusted(name, guid)
	if trusted then return end

	if trusted == nil then
		-- Guild roster not loaded: ask for it and decide when it arrives (max GUILD_WAIT s).
		local token = {}
		pending = { name = name, guid = guid, questSessionActive = questSessionActive, token = token }
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		C_Timer.After(GUILD_WAIT, function()
			if pending and pending.token == token then ResolvePending() end
		end)
		return
	end
	Reject(name, questSessionActive)
end

-- Join requests ("Name requests to join your group", incl. Quick Join): the
-- GROUP_INVITE_CONFIRMATION popup, shown to the group leader. Only the REQUEST
-- type is handled; SUGGEST (a group member suggests someone) is left alone.
local INVITE_CONFIRMATION_REQUEST = LE_INVITE_CONFIRMATION_REQUEST or 1
local joinWait -- token while join requests wait for the guild roster

local function HideJoinPopup(guid)
	if StaticPopup_Hide then StaticPopup_Hide("GROUP_INVITE_CONFIRMATION", guid) end
end

-- Decline every untrusted join request at the front of the queue.
-- final = the guild roster wait is over (unknown counts as not trusted).
local function ProcessJoinRequests(final)
	if not IsEnabled() then return end
	if type(GetNextPendingInviteConfirmation) ~= "function"
		or type(GetInviteConfirmationInfo) ~= "function"
		or type(RespondToInviteConfirmation) ~= "function" then return end

	local seen = {}
	for _ = 1, 40 do
		local ok, guid = pcall(GetNextPendingInviteConfirmation)
		if not ok or not guid or seen[guid] then return end
		seen[guid] = true

		local okInfo, confirmationType, name, playerGUID = pcall(GetInviteConfirmationInfo, guid)
		if not okInfo or confirmationType ~= INVITE_CONFIRMATION_REQUEST then return end

		local trusted = IsTrusted(name, playerGUID or guid)
		if trusted then return end
		if trusted == nil and not final then
			-- Guild roster not loaded: ask for it and decide when it arrives (max GUILD_WAIT s).
			if not joinWait then
				local token = {}
				joinWait = token
				if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
				C_Timer.After(GUILD_WAIT, function()
					if joinWait == token then
						joinWait = nil
						ProcessJoinRequests(true)
					end
				end)
			end
			return
		end

		-- Blizzard's own dialog relies on the answer removing the request at once,
		-- so a request still first in the queue means the call was blocked.
		local responded = pcall(RespondToInviteConfirmation, guid, false)
		if responded then
			local okNext, nextGuid = pcall(GetNextPendingInviteConfirmation)
			if okNext and nextGuid == guid then responded = false end
		end
		if not responded then
			PrintThrottled(name, "join request from " .. NameText(name) .. " (not a friend or guild member) - couldn't decline it, left for you to answer.")
			return
		end
		HideJoinPopup(guid)
		C_Timer.After(0, function() HideJoinPopup(guid) end)
		PrintThrottled(name, "declined a request to join your group from " .. NameText(name) .. ".")
	end
end

local function OnGuildRosterUpdate()
	if pending and not GuildRosterMissing() then ResolvePending() end
	if joinWait and not GuildRosterMissing() then
		joinWait = nil
		ProcessJoinRequests(false)
	end
end

-- Minimap button: left-click turns the addon on/off, drag moves it round the
-- minimap; the icon is greyed out with a red X while off.
local button      -- built at PLAYER_LOGIN
local tipOwner    -- frame the tooltip was last shown for

local function ColorOf(c, r, g, b)
	if type(c) == "table" and c.GetRGB then return c:GetRGB() end
	return r, g, b
end

local function FillTooltip(tt)
	tt:SetText("Only Friends", ColorOf(HIGHLIGHT_FONT_COLOR, 1, 1, 1))
	if IsEnabled() then
		tt:AddLine("On", ColorOf(GREEN_FONT_COLOR, 0.1, 1, 0.1))
		tt:AddLine("Invites from players who aren't friends or guild members are declined.", ColorOf(NORMAL_FONT_COLOR, 1, 0.82, 0), true)
	else
		tt:AddLine("Off", ColorOf(RED_FONT_COLOR, 1, 0.1, 0.1))
		tt:AddLine("All invites are shown as normal.", ColorOf(NORMAL_FONT_COLOR, 1, 0.82, 0), true)
	end
	tt:AddLine(" ")
	local r, g, b = ColorOf(GRAY_FONT_COLOR, 0.5, 0.5, 0.5)
	tt:AddLine("Left-click: turn on/off", r, g, b)
	tt:AddLine("Drag: move this button", r, g, b)
	tt:AddLine("/of minimap: hide or show this button", r, g, b)
end

-- owner: the frame to anchor to; anything else (e.g. a menu that passes no
-- frame) shows the tooltip at the cursor.
local function ShowTooltip(owner)
	if type(owner) == "table" and owner.GetObjectType then
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		tipOwner = owner
	else
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		tipOwner = UIParent
	end
	FillTooltip(GameTooltip)
	GameTooltip:Show()
end

local function HideTooltip()
	tipOwner = nil
	GameTooltip:Hide()
end

-- Place the button on the minimap's edge at the saved angle (round, or square
-- when another addon says the minimap is square).
local function PositionButton()
	if not button then return end
	local angle = math.rad(OnlyFriendsDB.minimap.angle)
	local x, y = math.cos(angle), math.sin(angle)
	if SafeCall(GetMinimapShape) == "SQUARE" then
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m, y / m
	end
	local rx = (Minimap:GetWidth() or 140) / 2 + 10
	local ry = (Minimap:GetHeight() or 140) / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * rx, y * ry)
end

-- Show the on/off state (and the hide setting) on the button.
local function UpdateButton()
	if not button then return end
	local on = IsEnabled()
	button.icon:SetDesaturated(not on)
	local v = on and 1 or ART.offDim
	button.icon:SetVertexColor(v, v, v)
	button.offMark:SetShown(not on)
	button:SetShown(not OnlyFriendsDB.minimap.hide)
	if tipOwner and GameTooltip:IsShown() and GameTooltip:GetOwner() == tipOwner then
		FillTooltip(GameTooltip) -- SetText starts it afresh, the anchor stays
		GameTooltip:Show()
	end
end

local function SetEnabled(on)
	InitDB()
	OnlyFriendsDB.enabled = on and true or false
	if on then
		Print("on - invites from players who aren't friends or guild members are declined.")
	else
		Print("off - all invites are shown as normal.")
	end
	UpdateButton()
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	OnlyFriendsDB.minimap.angle = math.floor(angle * 10 + 0.5) / 10
	PositionButton()
end

local function CreateMinimapButton()
	if button or not Minimap then return end
	button = CreateFrame("Button", "OnlyFriendsMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(ART.highlight)

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(ART.background)
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
	button.background = bg

	local icon = button:CreateTexture(nil, "ARTWORK")
	if not icon:SetTexture(ART.icon) then icon:SetTexture(ART.iconFallback) end
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture(ART.border)
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	button.border = border

	local mark = button:CreateTexture(nil, "OVERLAY", nil, 2)
	mark:SetTexture(ART.offMark)
	mark:SetSize(13, 13)
	mark:SetPoint("CENTER", icon, "BOTTOMRIGHT", -1, 2)
	button.offMark = mark

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "LeftButton" then SetEnabled(not IsEnabled()) end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", HideTooltip)
	button:SetScript("OnDragStart", function(self)
		HideTooltip()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	PositionButton()
	UpdateButton()
end

-- Blizzard's addon-compartment menu (named in the .toc).
function OnlyFriends_CompartmentClick()
	SetEnabled(not IsEnabled())
end

function OnlyFriends_CompartmentOnEnter(_, menuButton)
	ShowTooltip(menuButton)
end

function OnlyFriends_CompartmentOnLeave()
	HideTooltip()
end

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			InitDB()
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		InitDB()
		CreateMinimapButton()
		self:UnregisterEvent("PLAYER_LOGIN")
	elseif event == "PARTY_INVITE_REQUEST" then
		if not IsEnabled() then return end
		local name, _, _, _, _, _, _, inviterGUID, questSessionActive = ...
		HandleInvite(name, inviterGUID, questSessionActive)
	elseif event == "GROUP_INVITE_CONFIRMATION" then
		ProcessJoinRequests(false)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnGuildRosterUpdate()
	end
end

local function SlashHandler(msg)
	InitDB()
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" then
		SetEnabled(true)
	elseif msg == "off" then
		SetEnabled(false)
	elseif msg == "minimap" then
		local mm = OnlyFriendsDB.minimap
		mm.hide = not mm.hide
		if mm.hide then
			Print("minimap button hidden - /of minimap shows it again.")
		else
			if not button then CreateMinimapButton() end
			Print("minimap button shown.")
		end
		UpdateButton()
	else
		Print((IsEnabled() and "on" or "off") .. ". Commands: /of on, /of off, /of minimap")
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("GROUP_INVITE_CONFIRMATION")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", OnEvent)

SLASH_ONLYFRIENDS1 = "/of"
SLASH_ONLYFRIENDS2 = "/onlyfriends"
SlashCmdList["ONLYFRIENDS"] = SlashHandler
