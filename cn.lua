
local isChineseSimplified = false
local success, result = pcall(function()
    local languageCode = game:GetService("LocalizationService").RobloxLocaleId
    return languageCode == "zh-cn" or languageCode == "zh-Hans" or languageCode:lower():find("zh") == 1
end)

if success and result then
    isChineseSimplified = true
else
    return
end

local player = game.Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local playerGui = player.PlayerGui

local translationCache = {}
local translatedCache = {}
local translatedObjects = {}

local YOUDAO_APP_ID = "015e4bc650d16a48"
local YOUDAO_APP_KEY = "wXwwoaeESXz9CzB3yeTDe54JuOzkVbH7"

local SUPPORTED_UI_TYPES = {
    "TextLabel", "TextButton", "TextBox", "Frame", 
    "ScrollingFrame", "ImageButton", "ImageLabel"
}

local DANGEROUS_COMMANDS = {
    "neon", "shine", "ghost", "gold", "spin", 
    "bighead", "smallhead", "giantdwarf", "squash"
}

local LANGUAGE_PATTERNS = {
    ["zh-CN"] = {
        pattern = "[\199-\244][\128-\191]*[\128-\191]",
        exclude = "[\227][\128-\191][\128-\191]"
    },
    ["zh-TW"] = {
        pattern = "[\227][\128-\191][\128-\191]"
    },
    ["ja"] = {
        pattern = "[\123-\125]|[\199-\244][\128-\191]*[\128-\191]",
        exclude = "[\199-\244][\128-\191]*[\128-\191]"
    },
    ["ko"] = {
        pattern = "[\234-\235][\128-\191][\128-\191]|[\236-\237][\128-\191][\128-\191]"
    },
    ["ar"] = {
        pattern = "[\216-\219][\128-\191]"
    },
    ["ru"] = {
        pattern = "[\208-\209][\128-\191]"
    },
    ["th"] = {
        pattern = "[\224-\231][\128-\191]"
    },
    ["en"] = {
        pattern = "[A-Za-z]",
        exclude = "[\199-\244][\128-\191]*[\128-\191]"
    }
}

local TARGET_LANGUAGE = "zh-CN"
local MAX_TEXT_LENGTH = 5000
local BATCH_SIZE = 20
local MAX_CACHE_SIZE = 3000
local MAX_CONCURRENT_REQUESTS = 10

local function isDangerousText(text)
    if not text or type(text) ~= "string" then return false end
    local lowerText = text:lower()
    for _, cmd in ipairs(DANGEROUS_COMMANDS) do
        if lowerText:find(cmd) then
            return true
        end
    end
    return false
end

local function shouldSkipTranslation(text)
    if not text or text == "" or translatedCache[text] then
        return true
    end
    
    if text:match("^%s*$") or 
       text:match("^[0-9%.%s,:/]+$") or 
       #text > MAX_TEXT_LENGTH or
       isDangerousText(text) then
        translatedCache[text] = text
        return true
    end
    
    return false
end

local function detectLanguage(text)
    if not text or type(text) ~= "string" or text == "" then
        return "en"
    end
    
    if text:match(LANGUAGE_PATTERNS["zh-CN"].pattern) and 
       (not LANGUAGE_PATTERNS["zh-CN"].exclude or not text:match(LANGUAGE_PATTERNS["zh-CN"].exclude)) then
        return "zh-CN"
    end
    
    if text:match(LANGUAGE_PATTERNS["zh-TW"].pattern) then
        return "zh-TW"
    end
    
    if text:match(LANGUAGE_PATTERNS["ja"].pattern) and 
       (not LANGUAGE_PATTERNS["ja"].exclude or not text:match(LANGUAGE_PATTERNS["ja"].exclude)) then
        return "ja"
    end
    
    if text:match(LANGUAGE_PATTERNS["ko"].pattern) then
        return "ko"
    end
    
    if text:match(LANGUAGE_PATTERNS["ar"].pattern) then
        return "ar"
    end
    
    if text:match(LANGUAGE_PATTERNS["ru"].pattern) then
        return "ru"
    end
    
    if text:match(LANGUAGE_PATTERNS["th"].pattern) then
        return "th"
    end
    
    return "en"
end

local function googleTranslate(text, targetLang, sourceLang)
    if not text or text == "" then return text end
    
    sourceLang = sourceLang or "auto"
    
    local cacheKey = "google_"..text.."|"..sourceLang.."|"..targetLang
    if translationCache[cacheKey] then
        return translationCache[cacheKey]
    end
    
    local url = string.format(
        "https://translate.googleapis.com/translate_a/single?client=gtx&sl=%s&tl=%s&dt=t&q=%s",
        sourceLang, targetLang, HttpService:UrlEncode(text)
    )
    
    local success, response = pcall(function()
        return game:HttpGet(url, true)
    end)
    
    if success and response then
        local success2, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if success2 and data and data[1] then
            local result = ""
            for i, segment in ipairs(data[1]) do
                if segment[1] then
                    result = result .. segment[1]
                end
            end
            
            if result ~= "" and result ~= text then
                translationCache[cacheKey] = result
                return result
            end
        end
    end
    
    return nil
end

local function youdaoTranslate(text, targetLang, sourceLang)
    if not text or text == "" then return text end
    
    sourceLang = sourceLang or "auto"
    
    local cacheKey = "youdao_"..text.."|"..sourceLang.."|"..targetLang
    if translationCache[cacheKey] then
        return translationCache[cacheKey]
    end
    
    local salt = tostring(tick())
    local input = text
    if #input > 20 then
        input = input:sub(1, 10) .. #input .. input:sub(-10)
    end
    
    local signStr = YOUDAO_APP_ID .. input .. salt .. YOUDAO_APP_KEY
    local sign = game:GetService("HashService"):ComputeMD5Async(signStr)
    
    local url = string.format(
        "https://openapi.youdao.com/api?q=%s&from=%s&to=%s&appKey=%s&salt=%s&sign=%s",
        HttpService:UrlEncode(text),
        sourceLang == "auto" and "auto" or sourceLang,
        targetLang,
        YOUDAO_APP_ID,
        salt,
        sign
    )
    
    local success, response = pcall(function()
        return game:HttpGet(url, true)
    end)
    
    if success and response then
        local success2, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if success2 and data and data.translation and data.translation[1] then
            local result = data.translation[1]
            
            if result ~= "" and result ~= text then
                translationCache[cacheKey] = result
                return result
            end
        end
    end
    
    return nil
end

local function translateText(text, targetLang, sourceLang)
    if not text or text == "" or text:match("^%s*$") then
        return text
    end
    
    if text:match("^[%d%p%s]+$") then
        return text
    end
    
    local detectedLang = detectLanguage(text)
    
    if detectedLang == "zh-CN" or detectedLang == "zh-TW" then
        return text
    end
    
    local result = googleTranslate(text, targetLang, sourceLang)
    if not result or result == text then
        result = youdaoTranslate(text, targetLang, sourceLang)
    end
    return result or text
end

local function getTextContent(gui)
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        return gui.Text
    elseif gui:IsA("ImageButton") or gui:IsA("ImageLabel") then
        return gui:GetAttribute("Text") or gui.Name
    end
    return nil
end

local function setTextContent(gui, text)
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        gui.Text = text
    elseif gui:IsA("ImageButton") or gui:IsA("ImageLabel") then
        gui:SetAttribute("OriginalText", getTextContent(gui))
        gui:SetAttribute("Text", text)
    end
end

local function parallelTranslateBatch(batch)
    local results = {}
    local completed = 0
    local total = #batch
    local activeRequests = 0
    
    local function processItem(item, index)
        if not translatedCache[item.text] then
            activeRequests = activeRequests + 1
            
            local success, translated = pcall(function()
                return translateText(item.text, TARGET_LANGUAGE, "auto")
            end)
            
            if success and translated and translated ~= item.text then
                results[item.gui] = translated
                translatedCache[item.text] = translated
            else
                translatedCache[item.text] = item.text
            end
            
            activeRequests = activeRequests - 1
        end
        completed = completed + 1
    end
    
    for i, item in ipairs(batch) do
        while activeRequests >= MAX_CONCURRENT_REQUESTS do
            task.wait()
        end
        
        task.spawn(processItem, item, i)
        
        if i % 5 == 0 then
            task.wait(0.001)
        end
    end
    
    while completed < total do
        task.wait()
    end
    
    return results, total
end

local function fastCollectElements()
    local elementsToTranslate = {}
    local guisToScan = {playerGui, CoreGui}
    
    for _, gui in ipairs(guisToScan) do
        if gui and gui:IsDescendantOf(game) then
            local descendants = gui:GetDescendants()
            for i = 1, #descendants do
                local guiObj = descendants[i]
                if not translatedObjects[guiObj] and table.find(SUPPORTED_UI_TYPES, guiObj.ClassName) then
                    local text = getTextContent(guiObj)
                    if text and text ~= "" and not shouldSkipTranslation(text) then
                        table.insert(elementsToTranslate, {
                            gui = guiObj,
                            text = text
                        })
                        translatedObjects[guiObj] = true
                    end
                end
            end
        end
    end
    
    return elementsToTranslate
end

local function translateAllElements()
    local totalTranslated = 0
    local elementsToTranslate = fastCollectElements()
    
    while #elementsToTranslate > 0 do
        for i = 1, #elementsToTranslate, BATCH_SIZE do
            local batch = {}
            local batchEnd = math.min(i + BATCH_SIZE - 1, #elementsToTranslate)
            
            for j = i, batchEnd do
                table.insert(batch, elementsToTranslate[j])
            end
            
            local batchResults, batchCount = parallelTranslateBatch(batch)
            totalTranslated = totalTranslated + batchCount
            
            for gui, translated in pairs(batchResults) do
                if gui and gui.Parent then
                    setTextContent(gui, translated)
                end
            end
            
            if batchCount > 0 then
                task.wait(0.01)
            end
        end
        
        elementsToTranslate = fastCollectElements()
    end
    
    if table.count(translatedCache) > MAX_CACHE_SIZE then
        local newCache = {}
        local i = 0
        for k, v in pairs(translatedCache) do
            if i < MAX_CACHE_SIZE / 2 then
                newCache[k] = v
                i = i + 1
            else
                break
            end
        end
        translatedCache = newCache
    end
    
    return totalTranslated
end

task.spawn(function()
    local commonTexts = {
        "Play", "Start", "Settings", "Options", "Exit", "Continue",
        "Back", "Next", "Yes", "No", "OK", "Cancel", "Loading"
    }
    
    for _, text in ipairs(commonTexts) do
        pcall(function()
            translateText(text, TARGET_LANGUAGE, "en")
        end)
    end
end)

task.wait(1)

local totalCount = translateAllElements()

if totalCount > 0 then
    print(string.format("切换中文完成", totalCount))
end



