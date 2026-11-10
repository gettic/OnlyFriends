-- Only Friends: declines party invites from players who are not your friends
-- (WoW or Battle.net) or in your guild.

local ADDON_NAME = ...
local PREFIX = "|cff33ff99Only Friends|r: "
local GUILD_WAIT = 3        -- seconds to wait for a late guild roster
local LINE_THROTTLE = 10    -- seconds between chat lines for the same inviter

local DEFAULTS = { dbVersion = 1, enabled = true }

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

local function OnGuildRosterUpdate()
	if pending and not GuildRosterMissing() then ResolvePending() end
end

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			InitDB()
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PARTY_INVITE_REQUEST" then
		if not IsEnabled() then return end
		local name, _, _, _, _, _, _, inviterGUID, questSessionActive = ...
		HandleInvite(name, inviterGUID, questSessionActive)
	elseif event == "GUILD_ROSTER_UPDATE" then
		OnGuildRosterUpdate()
	end
end

local function SlashHandler(msg)
	InitDB()
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "on" then
		OnlyFriendsDB.enabled = true
		Print("on - invites from players who aren't friends or guild members are declined.")
	elseif msg == "off" then
		OnlyFriendsDB.enabled = false
		Print("off - all invites are shown as normal.")
	else
		Print((IsEnabled() and "on" or "off") .. ". Commands: /of on, /of off")
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", OnEvent)

SLASH_ONLYFRIENDS1 = "/of"
SLASH_ONLYFRIENDS2 = "/onlyfriends"
SlashCmdList["ONLYFRIENDS"] = SlashHandler
