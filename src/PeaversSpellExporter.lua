local addonName, addon = ...
local PeaversSpellExporter = CreateFrame("Frame")

-- Initialize the database
_G["PeaversSpellExporterDB"] = _G["PeaversSpellExporterDB"] or {
    classes = {},
    spellNames = {} -- Global cache for spell names
}
-- Create a local reference
local SpellExporterDB = _G["PeaversSpellExporterDB"]
-- Get player information
local function GetPlayerInfo()
    local _, playerClass = UnitClass("player")
    local specName = "Default"
    -- Try to get specialization info if available
    if GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex and GetSpecializationInfo then
            local _, name = GetSpecializationInfo(specIndex)
            if name then
                specName = name
            end
        end
    end
    return playerClass, specName
end
-- Safe function call wrapper
local function SafeCall(func, ...)
    if type(func) == "function" then
        return pcall(func, ...)
    end
    return false, "Function does not exist"
end
-- Improved spell name resolution using C_Spell API
local function GetSpellNameByID(spellID)
    -- Check if we already have this spell name cached
    if SpellExporterDB.spellNames[spellID] then
        return SpellExporterDB.spellNames[spellID]
    end
    -- Try C_Spell.GetSpellInfo if available
    if C_Spell and C_Spell.GetSpellInfo then
        local success, spellInfo = SafeCall(C_Spell.GetSpellInfo, spellID)
        if success and spellInfo and spellInfo.name and spellInfo.name ~= "" then
            SpellExporterDB.spellNames[spellID] = spellInfo.name
            return spellInfo.name
        end
    end
    -- Try C_Spell.GetSpellName if available (modern API)
    if C_Spell and C_Spell.GetSpellName then
        local success, spellName = SafeCall(C_Spell.GetSpellName, spellID)
        if success and spellName and spellName ~= "" then
            SpellExporterDB.spellNames[spellID] = spellName
            return spellName
        end
    end
    -- Fallback to Spell #ID format
    return "Spell #" .. spellID
end
-- Store a spell name in our global cache
local function StoreSpellName(spellID, spellName)
    if spellID and spellName and spellName ~= "" and spellName ~= ("Spell #" .. spellID) then
        SpellExporterDB.spellNames[spellID] = spellName
    end
end

-- Check if a spell is castable (not passive)
-- Added ignoreKnownCheck parameter to bypass IsSpellKnown check for talent scanning
local function IsSpellCastable(spellID, ignoreKnownCheck)
    -- First check if we can cast it, unless we're ignoring this check for talents
    if not ignoreKnownCheck and IsSpellKnown and not IsSpellKnown(spellID) then
        return false
    end

    -- Get spell info to check if it's passive
    local success, spellInfo
    if GetSpellInfo then
        success, spellInfo = SafeCall(GetSpellInfo, spellID)
    end

    -- Additional check using C_Spell API if available
    if C_Spell and C_Spell.GetSpellInfo then
        success, spellInfo = SafeCall(C_Spell.GetSpellInfo, spellID)
    end

    if success and spellInfo then
        -- Check if it's a passive ability
        if C_Spell and C_Spell.IsSpellPassive then
            local isPassive = C_Spell.IsSpellPassive(spellID)
            if isPassive then
                return false
            end
        end
    end

    -- Check if the spell is in the action bar API
    if IsUsableSpell then
        local canUse = select(1, IsUsableSpell(spellID))
        if canUse ~= nil then  -- If the spell is known to the action bar API
            return true
        end
    end

    -- Additional check - if it has a cooldown, it's likely castable
    if GetSpellBaseCooldown then
        local cooldown = GetSpellBaseCooldown(spellID)
        if cooldown and cooldown > 0 then
            return true
        end
    end

    return true  -- Default to including the spell if we can't determine
end

-- Main function to extract spells from the spellbook
local function ExtractSpellBookSpells()
    local playerClass, specName = GetPlayerInfo()
    -- Initialize class and spec in DB if needed
    if not SpellExporterDB.classes[playerClass] then
        SpellExporterDB.classes[playerClass] = {}
    end
    if not SpellExporterDB.classes[playerClass][specName] then
        SpellExporterDB.classes[playerClass][specName] = {}
    end
    local spellsTable = {}
    local spellsFound = 0
    local passiveSkipped = 0
    print("PeaversSpellExporter: Collecting castable spells for " .. playerClass .. " - " .. specName)
    -- Helper function to check if a spell exists in our table
    local function SpellExists(id)
        for _, spell in ipairs(spellsTable) do
            if spell.id == id then
                return true
            end
        end
        return false
    end
    -- Now scan the spellbook for this character
    print("PeaversSpellExporter: Scanning spellbook...")
    local bookTypes = {"spell"}
    if HasPetSpells and select(2, HasPetSpells()) then
        table.insert(bookTypes, "pet")
    end
    for _, bookType in ipairs(bookTypes) do
        local maxSlots = 1000 -- Use a large number to scan all possible slots
        for i = 1, maxSlots do
            local success, slotType, slotID = SafeCall(GetSpellBookItemInfo, i, bookType)
            if not success or not slotType then
                -- We've reached the end of valid spell slots
                break
            end
            if slotType == "SPELL" and slotID then
                -- Check if the spell is castable
                if IsSpellCastable(slotID) then
                    -- Try to get the spell name
                    local spellName = GetSpellNameByID(slotID)
                    if not SpellExists(slotID) then
                        table.insert(spellsTable, {
                            id = slotID,
                            name = spellName
                        })
                        spellsFound = spellsFound + 1
                    end
                else
                    passiveSkipped = passiveSkipped + 1
                end
            end
        end
    end
    print("PeaversSpellExporter: Found " .. spellsFound .. " castable spells in spellbook (skipped " .. passiveSkipped .. " passive abilities)")
    -- Scan talent tree for additional spells
    print("PeaversSpellExporter: Scanning talent tree...")
    local talentSpellsFound = 0
    local talentPassiveSkipped = 0
    -- Modern talent system (Dragonflight and later)
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID then
            local success, configInfo = SafeCall(C_Traits.GetConfigInfo, configID)
            if success and configInfo and configInfo.treeIDs then
                for _, treeID in ipairs(configInfo.treeIDs) do
                    local success2, nodes = SafeCall(C_Traits.GetTreeNodes, treeID)
                    if success2 and nodes then
                        for _, nodeID in ipairs(nodes) do
                            local success3, nodeInfo = SafeCall(C_Traits.GetNodeInfo, configID, nodeID)
                            if success3 and nodeInfo and nodeInfo.entryIDs then
                                for _, entryID in ipairs(nodeInfo.entryIDs) do
                                    local success4, entryInfo = SafeCall(C_Traits.GetEntryInfo, configID, entryID)
                                    if success4 and entryInfo and entryInfo.definitionID then
                                        local success5, definitionInfo = SafeCall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                                        if success5 and definitionInfo and definitionInfo.spellID and definitionInfo.spellID > 0 then
                                            -- Check if the spell is castable, ignoring whether it's known
                                            -- Pass true to ignoreKnownCheck for talents
                                            if IsSpellCastable(definitionInfo.spellID, true) then
                                                local spellName = GetSpellNameByID(definitionInfo.spellID)
                                                -- If we have a valid spell name from the talent tree, store it
                                                if spellName ~= ("Spell #" .. definitionInfo.spellID) then
                                                    StoreSpellName(definitionInfo.spellID, spellName)
                                                end
                                                if not SpellExists(definitionInfo.spellID) then
                                                    table.insert(spellsTable, {
                                                        id = definitionInfo.spellID,
                                                        name = spellName
                                                    })
                                                    talentSpellsFound = talentSpellsFound + 1
                                                end
                                            else
                                                talentPassiveSkipped = talentPassiveSkipped + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    print("PeaversSpellExporter: Found " .. talentSpellsFound .. " castable spells from talents (skipped " .. talentPassiveSkipped .. " passive abilities)")
    print("PeaversSpellExporter: Total found " .. #spellsTable .. " castable spells")
    -- Sort spells by ID
    table.sort(spellsTable, function(a, b) return a.id < b.id end)
    -- Store in the database
    SpellExporterDB.classes[playerClass][specName] = spellsTable
    return spellsTable
end
-- Try to resolve spell names using advanced methods
local function TryResolveSpellNames(spellsTable, callback)
    print("PeaversSpellExporter: Attempting to resolve spell names...")
    -- Count how many spells need resolution
    local needsResolution = 0
    for _, spell in ipairs(spellsTable) do
        if spell.name:find("^Spell #") then
            needsResolution = needsResolution + 1
        end
    end
    if needsResolution == 0 then
        print("PeaversSpellExporter: All spell names already resolved!")
        if callback then callback(spellsTable) end
        return
    end
    print("PeaversSpellExporter: " .. needsResolution .. " spells need name resolution")
    -- Use C_Spell.RequestLoadSpellData to preload spell data
    if C_Spell and C_Spell.RequestLoadSpellData then
        print("PeaversSpellExporter: Pre-loading spell data...")
        for _, spell in ipairs(spellsTable) do
            if spell.name:find("^Spell #") then
                C_Spell.RequestLoadSpellData(spell.id)
            end
        end
    end
    -- Create a timer to check for resolved spells
    local resolverFrame = CreateFrame("Frame")
    local processed = 0
    resolverFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
        -- Process every 0.5 seconds
        if self.timeSinceLastUpdate > 0.5 then
            self.timeSinceLastUpdate = 0
            local resolved = 0
            for i, spell in ipairs(spellsTable) do
                if spell.name:find("^Spell #") then
                    -- Try to get spell name
                    local newName = GetSpellNameByID(spell.id)
                    if newName ~= spell.name then
                        spellsTable[i].name = newName
                        resolved = resolved + 1
                        processed = processed + 1
                    end
                end
            end
            -- Update the progress
            if resolved > 0 then
                print("PeaversSpellExporter: Resolved " .. resolved .. " spell names")
            end
            -- Check if we need to continue
            local remaining = needsResolution - processed
            if remaining <= 0 or self.iterations >= 10 then
                print("PeaversSpellExporter: Finished resolving spell names: " .. processed .. " of " .. needsResolution .. " resolved")
                self:SetScript("OnUpdate", nil)
                if callback then callback(spellsTable) end
            end
            -- Increment iterations
            self.iterations = (self.iterations or 0) + 1
        end
    end)
end
-- Create UI frame for displaying spells
local function CreateSpellFrame()
    -- Check if frame already exists
    if _G["PeaversSpellExporterFrame"] then
        _G["PeaversSpellExporterFrame"]:Show()
        return _G["PeaversSpellExporterFrame"]
    end
    -- Create the main frame
    local frame = CreateFrame("Frame", "PeaversSpellExporterFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Set the title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
    frame.title:SetText("Peavers Spell Exporter - Castable Spells")
    -- Create a scrolling frame for the text
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    -- Create an edit box for the text
    frame.editBox = CreateFrame("EditBox", nil, frame.scrollFrame)
    frame.editBox:SetMultiLine(true)
    frame.editBox:SetFontObject(ChatFontNormal)
    frame.editBox:SetWidth(frame.scrollFrame:GetWidth())
    frame.editBox:SetAutoFocus(false)
    frame.editBox:SetScript("OnEscapePressed", function() frame.editBox:ClearFocus() end)
    -- Set the scrollframe content
    frame.scrollFrame:SetScrollChild(frame.editBox)
    return frame
end
-- Build text output from spell data
local function BuildSpellText(spells)
    if not spells or #spells == 0 then
        return "No castable spells found. Use /peaverspellexport scan to scan for spells."
    end
    -- Create header
    local playerClass, specName = GetPlayerInfo()
    local text = "Castable Spells for " .. playerClass .. " - " .. specName .. "\n"
    text = text .. "-------------------------------------------\n"
    text = text .. "SpellID,SpellName\n"
    -- Add each spell
    for _, spell in ipairs(spells) do
        text = text .. spell.id .. "," .. spell.name .. "\n"
    end
    return text
end
-- Show the spell UI
local function ShowSpellUI()
    local playerClass, specName = GetPlayerInfo()
    -- Get spell data
    local spells = {}
    if SpellExporterDB.classes[playerClass] and
       SpellExporterDB.classes[playerClass][specName] then
        spells = SpellExporterDB.classes[playerClass][specName]
    end
    -- If no spells found, extract them
    if #spells == 0 then
        spells = ExtractSpellBookSpells()
    end
    -- Create and show the frame
    local frame = CreateSpellFrame()
    -- Populate with spell data
    local text = BuildSpellText(spells)
    frame.editBox:SetText(text)
    -- Try to resolve any unknown spell names
    TryResolveSpellNames(spells, function(updatedSpells)
        local updatedText = BuildSpellText(updatedSpells)
        frame.editBox:SetText(updatedText)
    end)
    -- Show the frame
    frame:Show()
end
-- Register slash command
SLASH_PEAVERSSPELLEXPORTER1 = "/spellexport"
SlashCmdList["PEAVERSSPELLEXPORTER"] = function(msg)
    msg = msg or ""
    local command = strlower(msg)
    if command == "scan" then
        ExtractSpellBookSpells()
    elseif command == "show" then
        ShowSpellUI()
    elseif command == "clear" then
        -- Clear the database
        local playerClass, specName = GetPlayerInfo()
        if SpellExporterDB.classes[playerClass] then
            SpellExporterDB.classes[playerClass][specName] = {}
            print("PeaversSpellExporter: Cleared spell data for " .. playerClass .. " - " .. specName)
        end
    elseif command == "clearcache" then
        -- Clear the spell name cache
        SpellExporterDB.spellNames = {}
        print("PeaversSpellExporter: Cleared spell name cache")
    else
        -- Extract spells and show UI
        ExtractSpellBookSpells()
        ShowSpellUI()
    end
end
-- Register load event
PeaversSpellExporter:RegisterEvent("ADDON_LOADED")
PeaversSpellExporter:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        print("PeaversSpellExporter loaded. Type /peaverspellexport to scan castable spells and show results.")
    end
end)
