------------------------------------------------------------
-- GuildOnline
-- Minimap button that tracks online guild members
------------------------------------------------------------

local ADDON_NAME = ...
local ROW_HEIGHT = 18
local PANEL_WIDTH = 220
local MAX_VISIBLE_ROWS = 15

------------------------------------------------------------
-- Saved variables / defaults
------------------------------------------------------------

GuildOnlineDB = GuildOnlineDB or {}

local function InitDB()
    if GuildOnlineDB.minimapPos == nil then
        GuildOnlineDB.minimapPos = 220 -- degrees around the minimap
    end
    if GuildOnlineDB.radiusOffset == nil then
        GuildOnlineDB.radiusOffset = -5 -- extra clearance past the minimap's compass points
    end
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function InvitePlayer(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

local function WhisperPlayer(name)
    ChatFrame_SendTell(name)
end

local function GetClassColorForToken(classFileName)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFileName)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Builds a sorted list of online guild members: { name, zone, classFileName, level }
local function GetOnlineGuildMembers()
    local members = {}

    if not IsInGuild() then
        return members
    end

    local numTotal, numOnline = GetNumGuildMembers()
    for i = 1, numTotal do
        local name, _, _, level, _, zone, _, _, isOnline, _, classFileName = GetGuildRosterInfo(i)
        if name and isOnline then
            local shortName = Ambiguate and Ambiguate(name, "guild") or name
            table.insert(members, {
                fullName = name,
                displayName = shortName,
                zone = zone or "",
                classFileName = classFileName,
                level = level,
            })
        end
    end

    table.sort(members, function(a, b) return a.displayName < b.displayName end)
    return members
end

------------------------------------------------------------
-- Mouseover panel (list of online members)
------------------------------------------------------------

local panel = CreateFrame("Frame", "GuildOnlinePanel", UIParent, "BackdropTemplate")
panel:SetSize(PANEL_WIDTH, 40)
panel:SetFrameStrata("TOOLTIP")
panel:Hide()
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0, 0, 0, 0.95)

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -8)
title:SetText("Guild Online") -- placeholder, updated dynamically

local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
hint:SetText("Shift-click: whisper   Ctrl-click: invite")

local function UpdatePanelTitle()
    if IsInGuild() then
        local guildName = GetGuildInfo("player")
        title:SetText(guildName or "Guild Online")
    else
        title:SetText("Guild Online")
    end
end

local rowPool = {}

local function GetRow(index)
    local row = rowPool[index]
    if not row then
        row = CreateFrame("Button", nil, panel)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
        row:SetPoint("LEFT", panel, "LEFT", 10, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetJustifyH("LEFT")

        row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.zoneText:SetPoint("RIGHT", 0, 0)
        row.zoneText:SetJustifyH("RIGHT")

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.1)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self)
            if not self.fullName then return end
            if IsShiftKeyDown() then
                WhisperPlayer(self.fullName)
                panel:Hide()
            elseif IsControlKeyDown() then
                InvitePlayer(self.fullName)
            end
        end)

        rowPool[index] = row
    end
    return row
end

local function RefreshPanel()
    UpdatePanelTitle()

    local members = GetOnlineGuildMembers()
    local count = #members

    for i, row in ipairs(rowPool) do
        row:Hide()
    end

    local shown = math.min(count, MAX_VISIBLE_ROWS)
    local prevAnchor = hint

    for i = 1, shown do
        local m = members[i]
        local row = GetRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, i == 1 and -6 or 0)
        row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

        local r, g, b = GetClassColorForToken(m.classFileName)
        row.text:SetTextColor(r, g, b)
        row.text:SetText(m.displayName)
        row.zoneText:SetText(m.zone)
        row.fullName = m.fullName
        row:Show()

        prevAnchor = row
    end

    if count == 0 then
        local row = GetRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
        row.text:SetTextColor(0.6, 0.6, 0.6)
        row.text:SetText("No guild members online")
        row.zoneText:SetText("")
        row.fullName = nil
        row:Show()
        shown = 1
    end

    if count > MAX_VISIBLE_ROWS then
        local overflow = panel.overflowText
        if not overflow then
            overflow = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            panel.overflowText = overflow
        end
        overflow:ClearAllPoints()
        overflow:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -2)
        overflow:SetText(("...and %d more"):format(count - MAX_VISIBLE_ROWS))
        overflow:Show()
        shown = shown + 1
    elseif panel.overflowText then
        panel.overflowText:Hide()
    end

    panel:SetHeight(28 + 14 + (shown * ROW_HEIGHT) + 10)
end

------------------------------------------------------------
-- Minimap button
------------------------------------------------------------

local button = CreateFrame("Button", "GuildOnlineMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")

local bg = button:CreateTexture(nil, "BACKGROUND")
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetSize(20, 20)
bg:SetPoint("CENTER", 0, 1)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-BuyTab")
icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 1)

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetSize(53, 53)
overlay:SetPoint("TOPLEFT")

local countText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
countText:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
countText:SetTextColor(0.2, 1, 0.2)

------------------------------------------------------------
-- Minimap button positioning (handles round + square minimaps)
------------------------------------------------------------

-- capture Blizzard's real function BEFORE defining our own local with the same name
local Blizzard_GetMinimapShape = GetMinimapShape

local function GetMapShape()
    if Blizzard_GetMinimapShape then
        return Blizzard_GetMinimapShape()
    end
    return "ROUND"
end

local function UpdateButtonPosition()
    local angle = math.rad(GuildOnlineDB.minimapPos or 220)
    local minimapWidth = Minimap:GetWidth()
    local minimapHeight = Minimap:GetHeight()

    local buttonRadius = 10
    local extraPadding = GuildOnlineDB.radiusOffset or -5
    local radius = (math.min(minimapWidth, minimapHeight) / 2) + buttonRadius + extraPadding

    local cos, sin = math.cos(angle), math.sin(angle)
    local x, y = cos * radius, sin * radius

    local shape = GetMapShape()
    if shape and shape ~= "ROUND" then
        local halfW = (minimapWidth / 2) + buttonRadius + extraPadding
        local halfH = (minimapHeight / 2) + buttonRadius + extraPadding
        local xClamp = math.max(-halfW, math.min(halfW, x))
        local yClamp = math.max(-halfH, math.min(halfH, y))
        x, y = xClamp, yClamp
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        GuildOnlineDB.minimapPos = angle
        UpdateButtonPosition()
    end)
end)

button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

button:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "LeftButton" then
        if ToggleGuildFrame then
            ToggleGuildFrame()
        else
            if SlashCmdList and SlashCmdList["TOGGLEGUILDTAB"] then
                SlashCmdList["TOGGLEGUILDTAB"]("")
            end
        end
    end
end)

button:SetScript("OnEnter", function(self)
    RefreshPanel()
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, -4)
    panel:Show()
end)

local function HideIfNotHovered()
    if not (button:IsMouseOver() or panel:IsMouseOver()) then
        panel:Hide()
    end
end

button:SetScript("OnLeave", function(self)
    C_Timer.After(0.15, HideIfNotHovered)
end)

panel:SetScript("OnLeave", function(self)
    C_Timer.After(0.15, HideIfNotHovered)
end)

------------------------------------------------------------
-- Count text + roster updates
------------------------------------------------------------

local function UpdateCount()
    if not IsInGuild() then
        countText:SetText("")
        return
    end
    local _, numOnline = GetNumGuildMembers()
    countText:SetText(numOnline or 0)
    UpdatePanelTitle()

    if panel:IsShown() then
        RefreshPanel()
    end
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
        UpdateButtonPosition()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end
        UpdateButtonPosition()
    elseif event == "GUILD_ROSTER_UPDATE" then
        UpdateCount()
    elseif event == "PLAYER_GUILD_UPDATE" then
        UpdateCount()
    end
end)

-- Periodic refresh, respecting the ~10s server throttle on GuildRoster()
C_Timer.NewTicker(30, function()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end)

------------------------------------------------------------
-- Slash command: /gonline radius <number>
------------------------------------------------------------

SLASH_GUILDONLINE1 = "/gonline"
SlashCmdList["GUILDONLINE"] = function(msg)
    local cmd, value = msg:match("^(%S*)%s*(.-)$")
    if cmd == "radius" and tonumber(value) then
        GuildOnlineDB.radiusOffset = tonumber(value)
        UpdateButtonPosition()
        print(("GuildOnline: radius offset set to %d"):format(tonumber(value)))
    else
        print("GuildOnline: usage /gonline radius <number>  (current: " ..
            (GuildOnlineDB.radiusOffset or -5) .. ")")
    end
end