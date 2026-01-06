-- MyTalentList.lua
-- Versión 1.0:

SLASH_MYTALENTLIST1 = "/talents"

local function debugMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[MyTalents]|r " .. msg)
end

-- Limpieza para CSV
local function limpiarParaCSV(texto)
    if not texto then return '""' end
    texto = string.gsub(texto, '"', '""') 
    texto = string.gsub(texto, "\n", " ")
    texto = string.gsub(texto, "\r", "")
    return '"' .. texto .. '"'
end

-- Tabla para evitar duplicados globales
local procesados = {}

-- Generador de línea CSV
local function generarLinea(nombre, categoria, tipo, charges, desc)
    if procesados[nombre] then return nil end
    procesados[nombre] = true

    return limpiarParaCSV(categoria) .. "," .. 
           limpiarParaCSV(nombre) .. "," .. 
           limpiarParaCSV(tipo) .. "," .. 
           limpiarParaCSV(charges) .. "," .. 
           limpiarParaCSV(desc)
end

-- Obtener datos de un hechizo por ID
local function getSpellData(spellID)
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return nil end

    local name = spellInfo.name
    local desc = C_Spell.GetSpellDescription(spellID) or "Sin descripción"
    desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

    local isPassive = C_Spell.IsSpellPassive(spellID)
    local chargesInfo = "N/A"
    local chargeData = C_Spell.GetSpellCharges(spellID)

    if chargeData and chargeData.maxCharges and chargeData.maxCharges > 1 then
        chargesInfo = chargeData.maxCharges .. " Cargas"
        isPassive = false
    elseif not isPassive then
        chargesInfo = "Tiene CD"
    end

    local tipoStr = isPassive and "PASIVO" or "ACTIVO"
    return name, tipoStr, chargesInfo, desc
end

SlashCmdList["MYTALENTLIST"] = function(msg)
    debugMsg("Generando lista filtrada por tu Especialización...")
    
    procesados = {} 
    local csvLines = {}
    local tierSetNameCache = "Tier Set Desconocido"
    
    -- Encabezados
    table.insert(csvLines, '"Categoría","Talento/Hechizo","Tipo","Cargas/CD","Descripción"')

    -- =========================================================================
    -- PASO PREVIO: IDENTIFICAR SPECS A IGNORAR
    -- =========================================================================
    local specsIgnorar = {}
    local currentSpecIndex = GetSpecialization()
    
    if currentSpecIndex then
        for i = 1, GetNumSpecializations() do
            if i ~= currentSpecIndex then
                local _, specName = GetSpecializationInfo(i)
                if specName then
                    specsIgnorar[specName] = true
                end
            end
        end
    end

    -- =========================================================================
    -- SECCIÓN 1: TIER SETS (SCANNER VISUAL)
    -- =========================================================================
    local slotsPrioridad = {5, 1, 7, 3, 10} 
    local bonusEncontrados = 0

    for _, slot in ipairs(slotsPrioridad) do
        local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
        
        if tooltipData and tooltipData.lines then
            -- Buscar nombre del set
            for _, line in ipairs(tooltipData.lines) do
                local text = line.leftText
                if text and string.find(text, "%(%d+/%d+%)") then 
                     tierSetNameCache = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%(%d+/%d+%)", ""):gsub("^%s*", ""):gsub("%s*$", "")
                     break 
                end
            end

            -- Buscar Bonus Activos (Verdes)
            for _, line in ipairs(tooltipData.lines) do
                local rawText = line.leftText
                local color = line.leftColor

                if rawText then
                    local cleanText = rawText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    
                    if string.find(cleanText, "^Set:") then
                        -- Verificar color Verde/Blanco (Activo)
                        local esActivo = (color.g > 0.9 and color.r < 0.2) or (color.r == 1 and color.g == 1 and color.b == 1) 
                        
                        if esActivo then
                            bonusEncontrados = bonusEncontrados + 1
                            local nombreBonus = tierSetNameCache .. " (Bonus " .. bonusEncontrados .. ")"
                            local descripcionFinal = cleanText:gsub("^Set:%s*", "")
                            
                            local linea = generarLinea(nombreBonus, "TIER SET", "BONUS ACTIVO", "N/A", descripcionFinal)
                            if linea then table.insert(csvLines, linea) end
                        end
                    end
                end
            end
        end
        if bonusEncontrados > 0 then break end
    end

    -- =========================================================================
    -- SECCIÓN 2: ARBOL DE TALENTOS
    -- =========================================================================
    local configID = C_ClassTalents.GetActiveConfigID()
    if configID then
        local configInfo = C_Traits.GetConfigInfo(configID)
        local treeID = configInfo and configInfo.treeIDs[1]
        local nodes = treeID and C_Traits.GetTreeNodes(treeID)
        
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.ranksPurchased > 0 then
                    local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
                    if not activeEntryID and nodeInfo.entryIDs then activeEntryID = nodeInfo.entryIDs[1] end

                    if activeEntryID then
                        local entryInfo = C_Traits.GetEntryInfo(configID, activeEntryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo and defInfo.spellID then
                                local name, tipo, charges, desc = getSpellData(defInfo.spellID)
                                if name then
                                    local linea = generarLinea(name, "TALENTOS", tipo, charges, desc)
                                    if linea then table.insert(csvLines, linea) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- =========================================================================
    -- SECCIÓN 3: LIBRO DE HECHIZOS (FILTRADO)
    -- =========================================================================
    local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for i = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
        
        if skillLineInfo then
            local nombrePestana = skillLineInfo.name
            if nombrePestana and not specsIgnorar[nombrePestana] then
            
                local offset = skillLineInfo.itemIndexOffset
                local count = skillLineInfo.numSpellBookItems
                local categoryName = "LIBRO (" .. nombrePestana .. ")"
                
                for k = 1, count do
                    local slotIndex = offset + k
                    local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, Enum.SpellBookSpellBank.Player)
                    if info and info.spellID then
                        local tipoLibro = info.itemType
                        if (tipoLibro == 1 or tipoLibro == 2) then
                            local name, tipo, charges, desc = getSpellData(info.spellID)
                            if name then
                                local linea = generarLinea(name, categoryName, tipo, charges, desc)
                                if linea then table.insert(csvLines, linea) end
                            end
                        end
                    end
                end
            end
        end
    end

    local outputText = table.concat(csvLines, "\n")
    debugMsg("¡Listo!")
    ShowExportWindow(outputText)
end

function ShowExportWindow(text)
    local f = MyTalentFrame or CreateFrame("Frame", "MyTalentFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(700, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    
    if not f.title then
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
        f.title:SetText("Lista CSV (Filtrada por Spec)")
    end
    
    if not f.closeBtn then
        f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    end

    if not f.scrollFrame then
        f.scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.scrollFrame:SetPoint("TOPLEFT", 10, -30)
        f.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
        
        local editBox = CreateFrame("EditBox", nil, f.scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(650) 
        f.scrollFrame:SetScrollChild(editBox)
        f.editBox = editBox
    end

    f.editBox:SetText(text)
    f.editBox:HighlightText()
    f:Show()
end