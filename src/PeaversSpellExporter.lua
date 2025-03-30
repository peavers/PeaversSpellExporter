local addonName, addon = ...
local SimpleSpellExporter = CreateFrame("Frame")

-- Initialize the database
_G["SimpleSpellExporterDB"] = _G["SimpleSpellExporterDB"] or {
    classes = {},
    spellNames = {} -- Global cache for spell names
}

-- Create a local reference
local SpellExporterDB = _G["SimpleSpellExporterDB"]

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

    print("SimpleSpellExporter: Collecting spells for " .. playerClass .. " - " .. specName)

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
    print("SimpleSpellExporter: Scanning spellbook...")
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
                -- Try to get the spell name
                local spellName = GetSpellNameByID(slotID)

                if not SpellExists(slotID) then
                    table.insert(spellsTable, {
                        id = slotID,
                        name = spellName
                    })
                    spellsFound = spellsFound + 1
                end
            end
        end
    end

    print("SimpleSpellExporter: Found " .. spellsFound .. " spells in spellbook")

    -- Scan talent tree for additional spells
    print("SimpleSpellExporter: Scanning talent tree...")
    local talentSpellsFound = 0

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

    print("SimpleSpellExporter: Found " .. talentSpellsFound .. " spells from talents")
    print("SimpleSpellExporter: Total found " .. #spellsTable .. " spells")

    -- Sort spells by ID
    table.sort(spellsTable, function(a, b) return a.id < b.id end)

    -- Store in the database
    SpellExporterDB.classes[playerClass][specName] = spellsTable

    return spellsTable
end

-- Try to resolve spell names using advanced methods
local function TryResolveSpellNames(spellsTable, callback)
    print("SimpleSpellExporter: Attempting to resolve spell names...")

    -- Count how many spells need resolution
    local needsResolution = 0
    for _, spell in ipairs(spellsTable) do
        if spell.name:find("^Spell #") then
            needsResolution = needsResolution + 1
        end
    end

    if needsResolution == 0 then
        print("SimpleSpellExporter: All spell names already resolved!")
        if callback then callback(spellsTable) end
        return
    end

    print("SimpleSpellExporter: " .. needsResolution .. " spells need name resolution")

    -- Use C_Spell.RequestLoadSpellData to preload spell data
    if C_Spell and C_Spell.RequestLoadSpellData then
        print("SimpleSpellExporter: Pre-loading spell data...")
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
                print("SimpleSpellExporter: Resolved " .. resolved .. " spell names")
            end

            -- Check if we need to continue
            local remaining = needsResolution - processed
            if remaining <= 0 or self.iterations >= 10 then
                print("SimpleSpellExporter: Finished resolving spell names: " .. processed .. " of " .. needsResolution .. " resolved")
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
    if _G["SimpleSpellExporterFrame"] then
        _G["SimpleSpellExporterFrame"]:Show()
        return _G["SimpleSpellExporterFrame"]
    end

    -- Create the main frame
    local frame = CreateFrame("Frame", "SimpleSpellExporterFrame", UIParent, "BasicFrameTemplateWithInset")
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
    frame.title:SetText("Simple Spell Exporter")

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
        return "No spells found. Use /spellexport scan to scan for spells."
    end

    -- Create header
    local playerClass, specName = GetPlayerInfo()
    local text = "Spells for " .. playerClass .. " - " .. specName .. "\n"
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
SLASH_SIMPLESPELLEXPORTER1 = "/spellexport"
SlashCmdList["SIMPLESPELLEXPORTER"] = function(msg)
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
            print("SimpleSpellExporter: Cleared spell data for " .. playerClass .. " - " .. specName)
        end
    elseif command == "clearcache" then
        -- Clear the spell name cache
        SpellExporterDB.spellNames = {}
        print("SimpleSpellExporter: Cleared spell name cache")
    else
        -- Extract spells and show UI
        ExtractSpellBookSpells()
        ShowSpellUI()
    end
end

-- Register load event
SimpleSpellExporter:RegisterEvent("ADDON_LOADED")
SimpleSpellExporter:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        print("SimpleSpellExporter loaded. Type /spellexport to scan spells and show results.")
    end
end)