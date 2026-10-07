script_name("Auto-Interaction Securities")
script_author('yargoff')
script_version("2.0.6.5")

local ev = require('samp.events')
local imgui = require 'mimgui'
local faicons = require('fAwesome6')
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local colortag = '{c99732}'
local tag = colortag .. '[Auto-Interaction Securities]{ffffff}'
local smile = ':man:'
local base_color = 0xFFe69f35

function json(filePath)
    local configDir = getWorkingDirectory() .. '\\config'
    filePath = configDir .. '\\' .. (filePath:match('%.json$') and filePath or filePath .. '.json')
    local class = {}

    if not doesDirectoryExist(configDir) then createDirectory(configDir) end
    function class:Save(tbl)
        tbl = tbl or {}

        local file = io.open(filePath, 'w')
        if not file then return false, 'Не удалось открыть файл для записи' end

        local encoded = encodeJson(tbl)
        if not encoded then file:close() return false, 'Ошибка кодирования JSON' end

        file:write(encoded)
        file:close()

        return true, 'ok'
    end

    function class:Load(defaultTable)
        defaultTable = defaultTable or {}

        -- Файла нет — создаём новый
        if not doesFileExist(filePath) then self:Save(defaultTable) return defaultTable end

        local file = io.open(filePath, 'r')

        if not file then  return defaultTable end

        local content = file:read('*a')
        file:close()

        local data = {}

        -- Пустой файл
        if not content or content == '' then
            data = defaultTable
            self:Save(data)
            return data
        end

        -- Читаем JSON
        local ok, result = pcall(decodeJson, content)

        if ok and type(result) == 'table' then
            data = result
        else
            print('[JSON] Ошибка чтения файла: ' .. tostring(filePath))
            print('[JSON] Файл будет восстановлен.')

            data = defaultTable
            self:Save(data)

            return data
        end

        -- Рекурсивное объединение настроек
        local function copyTable(tbl)
            local result = {}

            for k, v in pairs(tbl) do
                if type(v) == 'table' then
                    result[k] = copyTable(v)
                else
                    result[k] = v
                end
            end

            return result
        end

        local function merge(dataTbl, defaultTbl)

            for k, defaultValue in pairs(defaultTbl) do

                -- Поля вообще нет
                if dataTbl[k] == nil then

                    if type(defaultValue) == 'table' then
                        dataTbl[k] = copyTable(defaultValue)
                    else
                        dataTbl[k] = defaultValue
                    end

                -- Оба значения таблицы
                elseif type(dataTbl[k]) == 'table'
                    and type(defaultValue) == 'table' then

                    -- Рекурсивно добавляем только отсутствующие поля
                    merge(dataTbl[k], defaultValue)

                end
            end
        end

        merge(data, defaultTable)

        -- Сохраняем обновлённую структуру
        self:Save(data)

        return data
    end

    return class
end
local name_file = 'Auto-Interaction Securities.json'
local settings = json(name_file):Load({
    AutoSpawnPet = false,
    ReducedCooldown = false,
    CheckingSecurityForSpawn = false,
    CheckStopPlayer = false,
    SOTG = false,
    InfoEat = {
        FirstSecurity = {
            autoeat = false,
            slot = 0,
            type = 0,
            quantity = 0
        },
        SecondSecurity = {
            autoeat = false,
            slot = 0,
            type = 0,
            quantity = 0
        },
        FeedingPet = {
            EveryHour = {
                status = false,
                time = 0
            },
            Satiety = {
                status = false,
                level = 0
            }
        },
    },
    Security = {},
    SpPet1 = {},
    SpPet2 = {},
    TimeSpawnPet = 0,
    debug_msg = false
})
local function save_settings()
    json(name_file):Save(settings)
end
local function load_settings()
    settings = json(name_file):Load(settings or {})
end

local function message(text, color)
    if not text or text == ' ' then return end
    if not color or color == ' ' then color = base_color end

    if smile then
        sampAddChatMessage(smile .. ' ' .. tag .. ' ' .. text, color)
    else
        sampAddChatMessage(tag .. ' ' .. text, color)
    end
end
local function console_msg(text)
    if not settings.debug_msg then return end
    if not text or text == ' ' then return end
    print(text)
end

settings.SpPet1 = settings.SpPet1 or {}
settings.SpPet2 = settings.SpPet2 or {}

local sppet1, sppet2 = false, false
local offpet1, offpet2 = false, false
local eatpet1, eatpet2 = false, false
local checkAllPet = false

local FeedingProcessing = false

local CheckAutoSpawn = false
local SpawnProcessing = false
local OffProcessing = false
local checkinv = false
local checksecurityinv = false
local StopedUpdateInfo = false

local AddVerifi = false

local renderWindow = imgui.new.bool(false)

local AutoSpPet = imgui.new.bool(settings.AutoSpawnPet or false)
local ReducedCooldown = imgui.new.bool(settings.ReducedCooldown or false)
local CheckingSecurityForSpawn = imgui.new.bool(settings.CheckingSecurityForSpawn or false)
local CheckStopPlayer = imgui.new.bool(settings.CheckStopPlayer or false)
local AutoEatPet1 = imgui.new.bool(settings.InfoEat.FirstSecurity.autoeat or false)
local AutoEatPet2 = imgui.new.bool(settings.InfoEat.SecondSecurity.autoeat or false)

local FeedingPet_EveryHour_status = imgui.new.bool(settings.InfoEat.FeedingPet.EveryHour.status or false)
local FeedingPet_EveryHour_time = imgui.new.int(settings.InfoEat.FeedingPet.EveryHour.time or 0)

local FeedingPet_Satiety_status = imgui.new.bool(settings.InfoEat.FeedingPet.Satiety.status or false)
local FeedingPet_Satiety_level = imgui.new.int(settings.InfoEat.FeedingPet.Satiety.level or 0)

local SOTG = imgui.new.bool(settings.SOTG or false)
local debug_msg = imgui.new.bool(settings.debug_msg or false)
local TimeSpawnPet = imgui.new.int(settings.TimeSpawnPet)

local typeEat = {
    [512] = 'Чипсы',
    [783] = 'Мясо',
    [1513] = 'Монеты охотника'
}

local foodIds = {}
for id in pairs(typeEat) do table.insert(foodIds, id) end
table.sort(foodIds)

local function getSecurityById(id)
    id = tonumber(id)
    if not id then return nil end
    for _, pet in ipairs(settings.Security or {}) do
        if tonumber(pet.id) == id then
            return pet
        end
    end
    return nil
end

local function AddVerifiSecurity(action)
    action = tostring(action or '')

    if AddVerifi then console_msg('[AddVer] Обновление информации уже запущено! Ожидайте завершения...') return false end

    if action == 'spawn' then
        wait(settings.ReducedCooldown and 3000 or 15000)
    elseif action == 'off' then
        wait(1200)
    else
        wait(1000)
    end

    if not sampIsLocalPlayerSpawned() then console_msg('[AddVer] Персонаж не подключен к серверу! Отменяю проверку...') return false end

    AddVerifi = true
    checkinv = false
    checksecurityinv = true

    local updated = false

    for i = 1, 40 do

        if StopedUpdateInfo then StopedUpdateInfo = false AddVerifi = false return false end
        if not sampIsLocalPlayerSpawned() then AddVerifi = false console_msg('[AddVer] Персонаж не подключен к серверу! Отменяю проверку...') return false end
        if checkinv and not checksecurityinv then console_msg('[AddVer] Информация о состоянии охранника/ов обновлена!') sendCEF('inventoryClose') updated = true break end

        wait(750)

        if StopedUpdateInfo then StopedUpdateInfo = false AddVerifi = false return false end

        if not sampIsLocalPlayerSpawned() then AddVerifi = false console_msg('[AddVer] Персонаж не подключен к серверу! Отменяю проверку...') return false end

        console_msg('[AddVer] Обновляю информацию о состоянии охранников [ ' .. i .. ' ]')

        checkinv = false
        checksecurityinv = true

        sampSendChat('/invent')

        local waitTime = 0
        while waitTime < 1500 do

            if StopedUpdateInfo then StopedUpdateInfo = false AddVerifi = false return false end
            if not sampIsLocalPlayerSpawned() then AddVerifi = false console_msg('[AddVer] Персонаж не подключен к серверу! Отменяю проверку...') return false end

            if checkinv and not checksecurityinv then console_msg('[AddVer] Информация о состоянии охранника/ов обновлена!') sendCEF('inventoryClose') updated = true break end

            wait(50)
            waitTime = waitTime + 50
        end

        if updated then break end

        console_msg('[AddVer] Ответ не получен, повторяю запрос...')
    end

    AddVerifi = false

    if not updated then console_msg('[AddVer] Не удалось обновить информацию о состоянии охранников!') return false end

    return true
end

local function updateSecuritySpawned(str)
    local securitiesArray = str:match('"securities"%s*:%s*%[(.-)%]')
    if not securitiesArray then return false end

    settings.Security = settings.Security or {}

    local securityById = {}

    for _, security in ipairs(settings.Security) do
        local id = tonumber(security.id)

        if id then
            security.id = id
            security.spawned = tonumber(security.spawned) or 0
            security.satiety = tonumber(security.satiety)
            securityById[id] = security
        end
    end

    local changed = false

    for obj in securitiesArray:gmatch('%b{}') do

        local name = obj:match('"name"%s*:%s*"([^"]*)"')
        local id = tonumber(obj:match('"id"%s*:%s*(%d+)'))
        local slot = tonumber(obj:match('"slot"%s*:%s*(%d+)'))
        local satiety = tonumber(obj:match('"satiety"%s*:%s*(%d+)'))
        local spawned = tonumber(obj:match('"spawned"%s*:%s*(%d+)'))

        if name and id and slot then

            spawned = spawned or 0

            local security = securityById[id]

            if not security then

                security = {
                    name = name,
                    id = id,
                    slot = slot,
                    satiety = satiety,
                    spawned = spawned
                }

                table.insert(settings.Security, security)

                securityById[id] = security
                changed = true

            else

                if security.spawned ~= spawned then
                    security.spawned = spawned
                    changed = true
                end

                if security.satiety ~= satiety then
                    security.satiety = satiety
                    changed = true
                end

                if security.name ~= name then
                    security.name = name
                    changed = true
                end

                if security.slot ~= slot then
                    security.slot = slot
                    changed = true
                end
            end
        end
    end

    return changed
end

local function CheckSpawnSecurity()
    local function isSpawned(pet)
        if not pet or not pet.id then return nil end
        local security = getSecurityById(pet.id)
        if not security then return nil end

        return tonumber(security.spawned) == 1
    end

    local spawned1 = isSpawned(settings.SpPet1)

    if spawned1 == nil then
        console_msg('[Check Spawn Security] Нет актуальной информации о первом охраннике.')

        if not AddVerifiSecurity() then return false end

        spawned1 = isSpawned(settings.SpPet1)

        if spawned1 == nil then console_msg('[Check Spawn Security] Не удалось получить состояние первого охранника.') return false end
    end

    if not settings.SOTG then
        if spawned1 then console_msg('[Check Spawn Security] Первый охранник уже заспавнен.') return false end

        return true
    end

    local spawned2 = isSpawned(settings.SpPet2)

    if spawned2 == nil then
        console_msg('[Check Spawn Security] Нет актуальной информации о втором охраннике.')

        if not AddVerifiSecurity() then return false end

        spawned1 = isSpawned(settings.SpPet1)
        spawned2 = isSpawned(settings.SpPet2)

        if spawned1 == nil or spawned2 == nil then console_msg('[Check Spawn Security] Не удалось получить состояние охранников.') return false end
    end

    if spawned1 and spawned2 then console_msg('[Check Spawn Security] Оба охранника уже заспавнены.') return false end

    return true
end

local function drawSecurityList()

    imgui.Text(faicons('shield') .. u8' Охранники')
    imgui.Separator()
    imgui.Spacing()

    local pet1 = settings.SpPet1
    local pet2 = settings.SpPet2

    imgui.Text(faicons('star'))
    imgui.SameLine()

    imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), u8'Основной:')

    imgui.SameLine()

    if pet1 and pet1.name then
        imgui.Text(u8(pet1.name .. ' [ID: ' .. tostring(pet1.id) .. ']'))
    else
        imgui.TextDisabled(u8'Не выбран')
    end

    imgui.Text(faicons('user_plus'))
    imgui.SameLine()

    imgui.TextColored(imgui.ImVec4(0.4, 0.8, 1.0, 1.0), u8'Второй:')

    imgui.SameLine()

    if settings.SOTG then
        if pet2 and pet2.name then
            imgui.Text(u8(pet2.name .. ' [ID: ' .. tostring(pet2.id) .. ']'))
        else
            imgui.TextDisabled(u8'Не выбран')
        end
    else
        imgui.TextDisabled(u8'Отключён')
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    local security = settings.Security or {}
    if #security == 0 then
        imgui.TextColored(imgui.ImVec4(0.8, 0.8, 0.8, 1), u8'Список охранников пуст')
        return
    end

    for i, pet in ipairs(security) do

        local id = tonumber(pet.id)
        local spawned = tonumber(pet.spawned) == 1
        local isMain = pet1 and tonumber(pet1.id) == id
        local isSecond = pet2 and tonumber(pet2.id) == id

        local satiety = tonumber(pet.satiety)

        if spawned then
            imgui.Text(faicons('circle_check'))
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1), u8'ЗАСПАВНЕН')
        else
            imgui.Text(faicons('circle_xmark'))
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(1.0, 0.35, 0.35, 1), u8'НЕ ЗАСПАВНЕН')
        end

        imgui.SameLine()
        imgui.Text(u8('| ' .. tostring(pet.name or 'Неизвестно')))

        if isMain then
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1), faicons('star') .. ' ' .. u8'ОСНОВНОЙ')
        elseif isSecond then
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.4, 0.8, 1.0, 1), faicons('user_plus') .. ' ' .. u8'ВТОРОЙ')
        end

        imgui.Text(u8(
            'ID: ' .. tostring(id or 'Неизвестно') ..
            ' | Slot: ' .. tostring(pet.slot or 'Неизвестно') ..
            ' | Сытость:'
        ))

        imgui.SameLine()

        if satiety then
            local satietyColor

            if satiety >= 70 then satietyColor = imgui.ImVec4(0.3, 1.0, 0.4, 1.0)
            elseif satiety >= 25 then satietyColor = imgui.ImVec4(1.0, 0.8, 0.2, 1.0)
            else satietyColor = imgui.ImVec4(1.0, 0.3, 0.3, 1.0)
            end

            imgui.TextColored(satietyColor, u8(tostring(satiety) .. '%'))
        else
            imgui.TextDisabled(u8'Неизвестна')
        end

        imgui.Spacing()

        if imgui.Button(faicons('star') .. u8' Основной##main' .. tostring(id), imgui.ImVec2(115, 27)) then
            settings.SpPet1 = {
                name = pet.name,
                id = pet.id,
                slot = pet.slot,
                satiety = pet.satiety,
                spawned = pet.spawned
            }

            save_settings()
            message('Основным выбран: ' .. tostring(pet.name))
        end

        imgui.SameLine()

        if imgui.Button(faicons('user_plus') .. u8' Второй##second' .. tostring(id), imgui.ImVec2(105, 27)) then
            settings.SpPet2 = {
                name = pet.name,
                id = pet.id,
                slot = pet.slot,
                satiety = pet.satiety,
                spawned = pet.spawned
            }

            save_settings()
            message('Вторым выбран: ' .. tostring(pet.name))
        end

        imgui.SameLine()

        if spawned then
            if imgui.Button(faicons('PERSON_WALKING') .. u8' Убрать##off' .. tostring(id), imgui.ImVec2(100, 27)) then
                if isMain then
                    lua_thread.create(OffPet, 1)
                elseif isSecond then
                    lua_thread.create(OffPet, 2)
                else
                    message('Сначала назначьте охранника основным или вторым.')
                end
            end
        else
            if imgui.Button(faicons('wand_magic_sparkles') .. u8' Призвать##spawn' .. tostring(id), imgui.ImVec2(100, 27)) then
                if isMain then
                    lua_thread.create(SpawnPet, 1)
                elseif isSecond then
                    if settings.SOTG then
                        lua_thread.create(SpawnPet, 2)
                    else
                        message('Включите режим двух охранников.')
                    end
                else
                    message('Сначала назначьте охранника основным или вторым.')
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
    end
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true

    local iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)

    solid = imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges)
    regular = imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('regular'), 14, config, iconRanges)

    theme()
end)

local newFrame = imgui.OnFrame(
    function() return renderWindow[0] end,
    function(player)
        local resX, resY = getScreenResolution()
        local sizeX, sizeY = 405, 680
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(sizeX, sizeY), imgui.Cond.FirstUseEver)
        if imgui.Begin('Auto-Interaction Securities ( ver. ' .. thisScript().version .. ' )', renderWindow, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoResize) then

            imgui.Text(faicons('shield') .. u8' Управление охранниками')

            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(faicons('wand_magic_sparkles') .. u8' Автопризыв охранника',AutoSpPet) then
                settings.AutoSpawnPet = AutoSpPet[0]
                save_settings()
            end

            if imgui.Checkbox(faicons('user_group') .. u8' Призыв двух охранников', SOTG) then
                settings.SOTG = SOTG[0]
                save_settings()
            end

            imgui.Spacing()

            imgui.Text(faicons('clock') .. u8' Задержка призыва')
            imgui.TextDisabled(u8'Охранники будут вызваны через ' .. tostring(settings.TimeSpawnPet) .. u8' сек. после подключения')
            if imgui.SliderInt(u8'##TimeSpawnPet',TimeSpawnPet, 0, 20) then
                settings.TimeSpawnPet = TimeSpawnPet[0]
                save_settings()
            end

            if imgui.Checkbox(faicons('PERSON_RUNNING') .. u8' Призыв после полной остановки', CheckStopPlayer) then
                settings.CheckStopPlayer = CheckStopPlayer[0]
                save_settings()
            end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.TextColored(imgui.ImVec4(0.55, 0.55, 0.55, 1.0), u8'Будет проверять персонажа на движение.')
                imgui.TextColored(imgui.ImVec4(0.55, 0.55, 0.55, 1.0), u8'Если включено, то скрипт будет ожидать полной остановки персонажа прежде чем начать призыв охранника')
                imgui.EndTooltip()
            end

            if imgui.Checkbox(faicons('SHIELD_CHECK') .. u8' Проверка охранников', CheckingSecurityForSpawn) then
                settings.CheckingSecurityForSpawn = CheckingSecurityForSpawn[0]
                save_settings()
            end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.TextDisabled(faicons('clock') .. u8' Автопроверка в 29:30 и 59:30 каждого часа')
                imgui.Text(u8'Проверяет, заспавнены ли выбранные охранники.')
                imgui.Text(u8'При включённом спавне двух охранников проверяются оба.')
                imgui.EndTooltip()
            end

            if imgui.Checkbox(faicons('bolt') .. u8' Уменьшенное КД на спавн', ReducedCooldown) then
                settings.ReducedCooldown = ReducedCooldown[0]
                save_settings()
            end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                imgui.TextDisabled(faicons('clock') .. u8' Сокращённое время ожидания спавна')
                imgui.Text(u8'Включить пункт в том случае если у вас КД спавна охранника составляет 3 секунды')
                imgui.EndTooltip()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            imgui.Text(faicons('fish') .. u8' Автокормление')

            if imgui.Checkbox(faicons('shield') .. u8' Основной охранник', AutoEatPet1) then
                settings.InfoEat.FirstSecurity.autoeat = AutoEatPet1[0]
                save_settings()
            end

            if settings.SOTG then
                if imgui.Checkbox(faicons('shield') .. u8' Второй охранник', AutoEatPet2) then
                    settings.InfoEat.SecondSecurity.autoeat = AutoEatPet2[0]
                    save_settings()
                end
            end

            imgui.Spacing()

            imgui.Text(faicons('utensils') .. u8' Выбор еды')
            imgui.Text(faicons('shield') .. u8' Основной охранник')

            local firstType = tonumber(settings.InfoEat.FirstSecurity.type) or 0
            local firstFood = typeEat[firstType]

            if firstFood then
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8(firstFood))
            else
                imgui.SameLine()
                imgui.TextDisabled(u8'Не выбрано')
            end

            local spacing = imgui.GetStyle().ItemSpacing.x
            local buttonWidth = (imgui.GetContentRegionAvail().x - spacing * 2) / 3

            for i, id in ipairs(foodIds) do
                local foodName = typeEat[id]

                if imgui.Button(u8(foodName) .. '##FirstFood' .. tostring(id), imgui.ImVec2(buttonWidth, 28)) then
                    settings.InfoEat.FirstSecurity.type = id
                    save_settings()

                    message('Основной охранник: выбрана еда - ' .. foodName)
                end

                if i < #foodIds then imgui.SameLine() end
            end

            if settings.SOTG then
                imgui.Spacing()

                imgui.Text(faicons('shield') .. u8' Второй охранник')

                local secondType = tonumber(settings.InfoEat.SecondSecurity.type) or 0
                local secondFood = typeEat[secondType]

                if secondFood then
                    imgui.SameLine()
                    imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8(secondFood))
                else
                    imgui.SameLine()
                    imgui.TextDisabled(u8'Не выбрано')
                end

                local spacing2 = imgui.GetStyle().ItemSpacing.x
                local buttonWidth2 = (imgui.GetContentRegionAvail().x - spacing2 * 2) / 3

                for i, id in ipairs(foodIds) do
                    local foodName = typeEat[id]

                    if imgui.Button(u8(foodName) .. '##SecondFood' .. tostring(id), imgui.ImVec2(buttonWidth2, 28)) then
                        settings.InfoEat.SecondSecurity.type = id
                        save_settings()

                        message('Второй охранник: выбрана еда — ' .. foodName)
                    end

                    if i < #foodIds then imgui.SameLine() end
                end
            end

            imgui.Spacing()
            if imgui.Button(faicons('rotate') .. u8' Обновить список охранников',imgui.ImVec2(-1, 32)) then
                lua_thread.create(CheckAllPet)
            end

            imgui.Spacing()

            drawSecurityList()

            imgui.Spacing()

            imgui.Text(faicons('utensils') .. u8' Способ автоматического кормления')
            imgui.Spacing()

            if imgui.Checkbox(u8'Кормить по времени', FeedingPet_EveryHour_status) then
                settings.InfoEat.FeedingPet.EveryHour.status = FeedingPet_EveryHour_status[0]

                if FeedingPet_EveryHour_status[0] then
                    FeedingPet_Satiety_status[0] = false
                    settings.InfoEat.FeedingPet.Satiety.status = false
                end

                save_settings()
            end

            if settings.InfoEat.FeedingPet.EveryHour.status then
                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8'Активно')

                imgui.Text(u8'Минута кормления: ' .. tostring(FeedingPet_EveryHour_time[0]))

                if imgui.SliderInt(u8'##FeedingPetEveryHourTime', FeedingPet_EveryHour_time, 0, 59) then
                    settings.InfoEat.FeedingPet.EveryHour.time = FeedingPet_EveryHour_time[0]
                    save_settings()
                end

                imgui.TextDisabled(u8'Кормление выполняется один раз в час в выбранную минуту.')
            end

            if imgui.Checkbox(u8'Кормить по уровню сытости', FeedingPet_Satiety_status) then

                settings.InfoEat.FeedingPet.Satiety.status = FeedingPet_Satiety_status[0]

                if FeedingPet_Satiety_status[0] then
                    FeedingPet_EveryHour_status[0] = false
                    settings.InfoEat.FeedingPet.EveryHour.status = false
                end

                save_settings()
            end

            if settings.InfoEat.FeedingPet.Satiety.status then

                imgui.SameLine()
                imgui.TextColored(imgui.ImVec4(0.3, 1.0, 0.4, 1.0), u8'Активно')

                imgui.Text(u8'Кормить при сытости: ' .. tostring(FeedingPet_Satiety_level[0]) .. '%')

                if imgui.SliderInt(u8'##FeedingPetSatietyLevel', FeedingPet_Satiety_level, 0, 100) then
                    settings.InfoEat.FeedingPet.Satiety.level = FeedingPet_Satiety_level[0]
                    save_settings()
                end

                imgui.PushTextWrapPos(imgui.GetWindowWidth() - 20)
                imgui.TextDisabled(u8('Кормление выполняется, когда сытость охранника опустится до указанного уровня.'))
                imgui.PopTextWrapPos()
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox(faicons('terminal') .. u8' DEBUG сообщения', debug_msg) then
                settings.debug_msg = debug_msg[0]
                save_settings()
            end

            imgui.End()
        end
    end
)
local ConnectionGeneration = 0
local wasSpawned = false
function main()
    while not isSampAvailable() do wait(0) end

    message('Скрипт загружен!')

    sampRegisterChatCommand('ais', function()
        renderWindow[0] = not renderWindow[0]
    end)

    sampRegisterChatCommand('sppet', function (arg)
        lua_thread.create(SpawnPet, tonumber(arg))
    end)
    sampRegisterChatCommand('offpet', function (arg)
        lua_thread.create(OffPet, tonumber(arg))
    end)

    sampRegisterChatCommand('fasteat', EatPet)

    sampRegisterChatCommand('aisallsppet', function ()
        lua_thread.create(function () AutoSpawnPet() end)
    end)

    sampRegisterChatCommand('aisallclear', function ()
        settings.Security = {}
        settings.SpPet1 = {}
        settings.SpPet2 = {}

        save_settings()
    end)

    sampRegisterChatCommand('aisreload', function ()
        thisScript():reload()
    end)

    while true do
        wait(0)

        local spawned = sampIsLocalPlayerSpawned()
        if wasSpawned and not spawned then
            ConnectionGeneration = ConnectionGeneration + 1

            SpawnProcessing = false
            CheckAutoSpawn = false

            sppet1 = false; sppet2 = false
            offpet1 = false; offpet2 = false
            eatpet1 = false; eatpet2 = false

            checkinv = false
            checksecurityinv = false
            checkAllPet = false
            AddVerifi = false

            console_msg('Соединение потеряно. Все активные процессы отменены.')
        end

        wasSpawned = spawned

        if not spawned then goto continue end

        local CheckSpawnPet = checkMSKTimeAdvanced('29, 59', 'once')
        if settings.AutoSpawnPet and settings.CheckingSecurityForSpawn and CheckSpawnPet then
            AutoSpawnPet()
        end

        if settings.InfoEat.FirstSecurity.autoeat then
            local feeding = settings.InfoEat.FeedingPet

            if offpet1 or offpet2 then return end

            if feeding.EveryHour.status then
                local CheckEat = checkMSKTimeAdvanced(tostring(feeding.EveryHour.time), 'once')
                if CheckEat then
                    message('Запускаю автокормежку охранника по указанному времени!')
                    console_msg('Запускаю автокормежку охранника по указанному времени!')
                    AutoEatPet()
                end
            elseif feeding.Satiety.status then
                if not FeedingProcessing then
                    local needEat1 = false
                    local needEat2 = false

                    local satietyLevel = tonumber(feeding.Satiety.level or 0)
                    if settings.InfoEat.FirstSecurity.autoeat and settings.SpPet1 and settings.SpPet1.id then

                        local mainId = tonumber(settings.SpPet1.id)
                        for _, pet in ipairs(settings.Security or {}) do
                            if tonumber(pet.id) == mainId then

                                local satiety = tonumber(pet.satiety)
                                local spawned = tonumber(pet.spawned) == 1

                                if spawned and satiety and satiety <= satietyLevel then needEat1 = true end

                                break
                            end
                        end
                    end

                    if settings.SOTG and settings.InfoEat.SecondSecurity.autoeat and settings.SpPet2 and settings.SpPet2.id then

                        local secondId = tonumber(settings.SpPet2.id)
                        for _, pet in ipairs(settings.Security or {}) do
                            if tonumber(pet.id) == secondId then

                                local satiety = tonumber(pet.satiety)
                                local spawned = tonumber(pet.spawned) == 1

                                if spawned and satiety and satiety <= satietyLevel then needEat2 = true end

                                break
                            end
                        end
                    end

                    if needEat1 or needEat2 then
                        FeedingProcessing = true

                        message('Сытость охранника ниже установленного уровня. Запускаю автокормежку!')
                        console_msg('Автокормление: основной = ' .. tostring(needEat1) .. ', второй = ' .. tostring(needEat2))

                        AutoEatPet()

                        if settings.SOTG then wait(5000) else wait(2750) end

                        FeedingProcessing = false
                    end
                end
            end
        end

        ::continue::

    end
end

function SpawnPet(arg)
    if SpawnProcessing then console_msg('Спавн охранника уже запущен! Ожидайте завершения...') return end

    local n = tonumber(arg) or 1
    if n ~= 1 and n ~= 2 then message('Использование: /sppet [1/2]') return end

    if not sampIsLocalPlayerSpawned() then console_msg('[SpPet] Персонаж не подключен к серверу! Отменяю спавн...') return false end

    SpawnProcessing = true

    sppet1 = n == 1
    sppet2 = n == 2

    emul_num({220, 0, 27, 64})

    for i = 1, 40 do
        wait(50)
        if checkinv then console_msg('[SpPet] Спавн охранника запущен!') break end
        if not sampIsLocalPlayerSpawned() then SpawnProcessing = false console_msg('[SpPet] Персонаж не подключен к серверу! Отменяю спавн...') return false end

        wait(750)

        if not sampIsLocalPlayerSpawned() then SpawnProcessing = false console_msg('[SpPet] Персонаж не подключен к серверу! Отменяю спавн...') return false end

        sampSendChat('/invent')
        console_msg('[SpPet] Попытка открыть инвентарь... [ ' .. i .. ' ]')

        wait(50)
        if checkinv then console_msg('[SpPet] Спавн охранника запущен!') break end
    end

    SpawnProcessing = false
end

function AutoSpawnPet()
    if CheckAutoSpawn then console_msg('[ASP] Автоматический спавн охранника уже запущен! Ожидайте завершения...') return end
    CheckAutoSpawn = true

    local function cancel()
        CheckAutoSpawn = false

        sppet1 = false
        sppet2 = false

        return false
    end

    local function isPlayerStopped()
        local vx, vy, vz = getCharVelocity(PLAYER_PED)
        return math.abs(vx) < 0.01 and math.abs(vy) < 0.01 and math.abs(vz) < 0.01
    end

    if settings.CheckStopPlayer and not isPlayerStopped() then
        message('[ASP] Ожидаю остановки персонажа...')

        while not isPlayerStopped() do console_msg('[ASP] Ожидаю остановки персонажа...') wait(100) end

        wait(500)

        if isPlayerStopped() then message('[ASP] Персонаж остановился. Призываю охранника...') end
    end

    if not sampIsLocalPlayerSpawned() then return cancel() end

    AddVerifiSecurity()

    wait(1000)

    if not sampIsLocalPlayerSpawned() then return cancel() end

    if not CheckSpawnSecurity() then CheckAutoSpawn = false return false end

    wait(350)

    if not sampIsLocalPlayerSpawned() then return cancel() end

    SpawnPet(1)
    if settings.SOTG then wait(settings.ReducedCooldown and 5550 or 17550) SpawnPet(2) end

    CheckAutoSpawn = false
end

function OffPet(arg)
    if OffProcessing then console_msg('Скрытие охранника уже запущено! Ожидайте завершения...') return end

    local n = tonumber(arg) or 1
    if n ~= 1 and n ~= 2 then message('Использование: /offpet [1/2]') return end

    OffProcessing = true

    offpet1 = n == 1
    offpet2 = n == 2

    emul_num({220, 0, 27, 64})

    for i = 1, 40 do
        wait(50)
        if checkinv then console_msg('Скрытие охранника запущено!') break end

        wait(750)

        sampSendChat('/invent')
        console_msg('[OffPet] Попытка открыть инвентарь [ ' .. i .. ' ]')

        wait(50)
        if checkinv then console_msg('Скрытие охранника запущено!') break end
    end

    OffProcessing = false
end

function EatPet(arg)
    local n = tonumber(arg) or 1
    if n ~= 1 and n ~= 2 then message('Использование: /fasteat [1/2]') return end

    eatpet1 = n == 1
    eatpet2 = n == 2

    console_msg('[EatPet] Начинаю кормежку охранника [ ' .. n .. ' ]')

    emul_num({220, 0, 27, 64})
    sampSendChat('/invent')
end

function AutoEatPet()
    EatPet(1)
    if settings.SOTG and settings.InfoEat.SecondSecurity.autoeat then
        wait(2750)
        EatPet(2)
        wait(1200)
    else
        wait(1000)
    end

    AddVerifiSecurity()
end

function CheckAllPet()
    checkAllPet = true
    emul_num({220, 0, 27, 64})
    sampSendChat('/invent')

    wait(500)
    load_settings()
end

addEventHandler('onReceivePacket', function (id, bs)
    if id == 220 then
        raknetBitStreamIgnoreBits(bs, 8)
        if (raknetBitStreamReadInt8(bs) == 17) then
            raknetBitStreamIgnoreBits(bs, 32)
            local length = raknetBitStreamReadInt16(bs)
            local encoded = raknetBitStreamReadInt8(bs)
            local str = (encoded ~= 0) and raknetBitStreamDecodeString(bs, length + encoded) or raknetBitStreamReadString(bs, length)

            local eatInfo = {
                settings.InfoEat.FirstSecurity,
                settings.InfoEat.SecondSecurity
            }

            for i = 1, 2 do
                local info = eatInfo[i]
                if info then
                    local slot, quantity = str:match('"slot":(%d+),"available":1,"blackout":0,"item":' .. tostring(info.type) .. ',"amount":(%d+)')

                    if slot then
                        info.slot = tonumber(slot)
                        info.quantity = tonumber(quantity) or 0
                    end

                    save_settings()
                end
            end

            local function HideInventory()
                local json = '[ null ]'
                local code = "window.executeEvent('event.setActiveView', `" .. json .. "`);"
                local bs = raknetNewBitStream()
                raknetBitStreamWriteInt8(bs, 17)
                raknetBitStreamWriteInt32(bs, 0)
                raknetBitStreamWriteInt16(bs, #code)
                raknetBitStreamWriteInt8(bs, 0)
                raknetBitStreamWriteString(bs, code)
                raknetEmulPacketReceiveBitStream(220, bs)
                raknetDeleteBitStream(bs)
            end

            if str:find('event.setActiveView', 1, true) and str:find('Inventory', 1, true) then
                if not checkinv then checkinv = true console_msg('Инвентарь открыт') end
                if not (checkAllPet or sppet1 or sppet2 or offpet1 or offpet2 or eatpet1 or eatpet2 or AddVerifi) then return end
                lua_thread.create(function ()
                    wait(450)

                    sendCEF('requestShowingInventory|28')
                    wait(250)

                    if sppet1 then
                        local pet = getSecurityById(settings.SpPet1.id)
                        if not pet then
                            message('Основной охранник не найден в списке.')
                            sppet1 = false
                            sendCEF('inventoryClose')

                        elseif tonumber(pet.spawned) == 1 then
                            message('Основной охранник {e0b42f}уже{ffffff} призван.')

                            sppet1 = false
                            sendCEF('inventoryClose')
                        else
                            sendCEF('clickOnMenu|{"id": ' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')

                            AddVerifiSecurity('spawn')
                        end
                    elseif sppet2 then
                        local pet = getSecurityById(settings.SpPet2.id)
                        if not pet then
                            message('Второй охранник не найден в списке.')
                            sppet2 = false
                            sendCEF('inventoryClose')

                        elseif tonumber(pet.spawned) == 1 then
                            message('Второй охранник {e0b42f}уже{ffffff} призван.')

                            sppet2 = false
                            sendCEF('inventoryClose')
                        else
                            sendCEF('clickOnMenu|{"id": ' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')

                            AddVerifiSecurity('spawn')
                        end
                    elseif offpet1 then
                        local pet = getSecurityById(settings.SpPet1.id)
                        if not pet then
                            message('Основной охранник не найден в списке.')
                            offpet1 = false
                            sendCEF('inventoryClose')

                        else
                            sendCEF('clickOnMenu|{"id": ' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')

                            AddVerifiSecurity('off')
                        end
                    elseif offpet2 then
                        local pet = getSecurityById(settings.SpPet2.id)
                        if not pet then
                            message('Второй охранник не найден в списке.')
                            offpet2 = false
                            sendCEF('inventoryClose')

                        else
                            sendCEF('clickOnMenu|{"id": ' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')

                            AddVerifiSecurity('off')
                        end
                    elseif eatpet1 then
                        local pet = getSecurityById(settings.SpPet1.id)
                        if not pet then
                            message('Основной охранник не найден в списке.')
                            eatpet1 = false
                            sendCEF('inventoryClose')

                        elseif tonumber(pet.spawned) ~= 1 then
                            message('Основной охранник не призван. Кормление отменено.')
                            eatpet1 = false
                            sendCEF('inventoryClose')

                        else
                            sendCEF('useItemOnSecurity|{"from":{"amount":' .. tonumber(settings.InfoEat.FirstSecurity.quantity or 0) .. ',"slot":' .. tonumber(settings.InfoEat.FirstSecurity.slot or 0) .. ',"type":1},"id":' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')
                        end
                    elseif eatpet2 then
                        local pet = getSecurityById(settings.SpPet2.id)
                        if not pet then
                            message('Второй охранник не найден в списке.')
                            eatpet2 = false
                            sendCEF('inventoryClose')

                        elseif tonumber(pet.spawned) ~= 1 then
                            message('Второй охранник не призван. Кормление отменено.')
                            eatpet2 = false
                            sendCEF('inventoryClose')

                        else
                            sendCEF('useItemOnSecurity|{"from":{"amount":' .. tonumber(settings.InfoEat.SecondSecurity.quantity or 0) .. ',"slot":' .. tonumber(settings.InfoEat.SecondSecurity.slot or 0) .. ',"type":1},"id":' .. tonumber(pet.id) .. '}')
                            sendCEF('inventoryClose')
                        end
                    end

                end)

                HideInventory()
            end

            if str:match('event.setActiveView') and str:match('null') and checkinv then checkinv = false console_msg('Инвентарь закрыт.') end

            if str:find('event.inventory.playerInventory', 1, true) and str:find('securities', 1, true) then
                local spawnedChanged = updateSecuritySpawned(str)
                if spawnedChanged then save_settings() spawnedChanged = false end

                if checksecurityinv then checksecurityinv = false sendCEF('inventoryClose') end

                if checkAllPet then
                    message('Сканирую всех охранников...')

                    local securitiesArray = str:match('"securities"%s*:%s*%[(.-)%]')
                    if not securitiesArray then message('Не удалось получить список охранников.') return end

                    settings.Security = {}

                    local securityById = {}
                    for _, security in ipairs(settings.Security) do
                        local id = tonumber(security.id)

                        if id then
                            security.id = id
                            security.spawned = tonumber(security.spawned) or 0

                            securityById[id] = security
                        end
                    end

                    for obj in securitiesArray:gmatch('%b{}') do

                        local name = obj:match('"name"%s*:%s*"([^"]*)"')
                        local id = tonumber(obj:match('"id"%s*:%s*(%d+)'))
                        local slot = tonumber(obj:match('"slot"%s*:%s*(%d+)'))
                        local satiety = tonumber(obj:match('"satiety"%s*:%s*(%d+)'))
                        local spawned = tonumber(obj:match('"spawned"%s*:%s*(%d+)'))

                        if name and id and slot then
                            spawned = spawned or 0
                            local security = securityById[id]

                            if security then
                                security.name = name
                                security.id = id
                                security.slot = slot
                                security.satiety = satiety
                                security.spawned = spawned
                            else
                                security = {
                                    name = name,
                                    id = id,
                                    slot = slot,
                                    satiety = satiety,
                                    spawned = spawned
                                }

                                table.insert(settings.Security, security)
                                securityById[id] = security
                            end

                            console_msg(string.format('Охранник: %s | ID: %d | Slot: %d | Spawned: %d | Satiety: %d', name, id, slot, spawned, satiety))
                        end
                    end

                    save_settings()
                    message('Информация обо всех охранниках {40e348}успешно{ffffff} получена!')

                    checkAllPet = false
                    sendCEF('inventoryClose')
                end
            end
        end
    end
end)

function ev.onShowDialog(id, st, tit, b1, b2, text)

    if tit:match('{BFBBBA}Призыв охранника') then
        lua_thread.create(function ()
            wait(1)
            sampCloseCurrentDialogWithButton(0)
        end)
        console_msg('[SpPet] Охранник успешно заспавнен!')
    end

    if tit:match('{BFBBBA}.+') then
        if sppet1 or sppet2 then
            lua_thread.create(function ()
                wait(1)

                if text:match('%{C0C0C0%}%[1%] %{FFFFFF%}Заспавнить рядом с собой') then
                    sampSendDialogResponse(id, 1, 0, '')
                elseif text:match('%{C0C0C0%}%[%d+%] %{FFFFFF%}Спрятать') then
                    message('Ваш охранник {e0b42f}уже{ffffff} заспавнен!')
                end

                sppet1, sppet2 = false, false
                sampCloseCurrentDialogWithButton(0)
            end)
        end

        if offpet1 or offpet2 then
            lua_thread.create(function ()
                wait(1)

                if text:match('%[%d+%] {.-}Отправить за доставкой') then
                    sampSendDialogResponse(id, 1, 1, '')
                elseif text:match('%{C0C0C0%}%[%d+%] %{FFFFFF%}Спрятать') then
                    sampSendDialogResponse(id, 1, 0, '')
                else
                    message('Ваш охранник {e0b42f}уже{ffffff} скрыт!')
                end

                offpet1, offpet2 = false, false
                sampCloseCurrentDialogWithButton(0)
            end)

            console_msg('[OffPet] Охранник успешно скрыт!')
        end
    end

    if tit:match('{BFBBBA}Покормить охранника') then
        lua_thread.create(function ()
            wait(1)
            sampSendDialogResponse(id, 1, nil, '')
        end)
    end

end

function ev.onServerMessage(color, text)
    local nameplayer = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)))

    if text:find('{DFCFCF}%[Подсказка%] {DC4747}На сервере есть инвентарь, используйте клавишу Y для работы с ним.') then
        if settings.AutoSpawnPet then
            lua_thread.create(function()
                local generation = ConnectionGeneration
                local timeout = settings.TimeSpawnPet * 1000

                wait(timeout)

                if generation ~= ConnectionGeneration then return end
                if not sampIsLocalPlayerSpawned() then return end

                AutoSpawnPet()
            end)
        end
	end

    if text:match(nameplayer..' накормил%(а%) своего охранника') then
        if (settings.InfoEat.FirstSecurity.autoeat or settings.InfoEat.SecondSecurity.autoeat) and settings.InfoEat.FeedingPet.EveryHour.status then
            eatpet1, eatpet2 = false, false
            message('Вы покормили своего друга! Ухожу в КД до следующего применения...')
        end
    end

    if text:match('Ваш личный охранник голоден, его необходимо покормить!') then
        lua_thread.create(AutoEatpet)
    end

    if text:match('Призыв личного охранника отменён!') and color == -1104335361 then
        message('Вы отменили призыв...')
        lua_thread.create(function ()
            sppet1, sppet2 = false, false
            if checkinv then sendCEF('inventoryClose') end
        end)
    end

    if text:match('%[Ошибка%] %{ffffff%}У вас нету охранников!') then
        console_msg('У вас нет ни одного охранника! Выгружаю скрипт!')
        thisScript():unload()
    end

    if text:match('%[Ошибка%] {ffffff}Подождите немного!') then
        return
    end

    if text:match('%[Ошибка%] {ffffff}Не флуди! %(2%)') then
        if AddVerifi and not StopedUpdateInfo then StopedUpdateInfo = true end
    end
end

local FreezePlayer = false
function ev.onDisplayGameText(style, time, text)

    if settings.AutoSpawnPet and text:match('2 sec') and not FreezePlayer  then
        FreezePlayer  = true

        lua_thread.create(function ()
            freezeCharPosition(PLAYER_PED, true)
            console_msg('Замораживаю координаты персонажа')

            wait(settings.ReducedCooldown and 5550 or 17550)

            freezeCharPosition(PLAYER_PED, false)
            console_msg('Размораживаю координаты персонажа')

            FreezePlayer  = false
        end)
    end

end

function ev.onPlayerQuit(playerId, reason)
    if playerId ~= select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)) then
        return
    end

    ConnectionGeneration = ConnectionGeneration + 1

    SpawnProcessing = false
    CheckAutoSpawn = false

    sppet1 = false
    sppet2 = false

    offpet1 = false
    offpet2 = false

    eatpet1 = false
    eatpet2 = false

    checkinv = false
    checksecurityinv = false
    checkAllPet = false
    AddVerifi = false

    console_msg('Персонаж вышел с сервера. Старые процессы отменены.')
end

sendCEF = function(str)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt16(bs, #str)
    raknetBitStreamWriteString(bs, str)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

function emul_num(array)
    local bs = raknetNewBitStream()
    for i, byte in ipairs(array) do
        raknetBitStreamWriteInt8(bs, byte)
    end
    raknetSendBitStream(bs)
    raknetDeleteBitStream(bs)
end

do
    local parsedCache = {}
    local timeState = {}

    local cachedStamp = -1
    local cachedSecondOfDay = 0
    local cachedMinute = 0
    local cachedSecond = 0

    local function compileSchedule(timeStr, defaultMode)
        local schedule = {}

        timeStr = tostring(timeStr or ""):gsub("%s+", "")
        for part in timeStr:gmatch("[^,]+") do

            local timePart, mode = part:match("^([^|]+)|?(%a*)$")
            if not timePart or timePart == "" then goto continue end
            if mode == "" then mode = defaultMode or "once" end

            local item = {
                mode = mode,
                key = timePart .. "|" .. mode
            }

            if timePart:sub(1, 1) == "@" then
                local value = timePart:sub(2)
                if value:find("-") then

                    local startValue, finishValue = value:match("^([^%-]+)%-(.+)$")
                    if startValue and finishValue then

                        local sm, ss = startValue:match("^(%d+):(%d+)$")
                        local em, es = finishValue:match("^(%d+):(%d+)$")
                        if sm and ss and em and es then

                            sm = tonumber(sm)
                            ss = tonumber(ss)
                            em = tonumber(em)
                            es = tonumber(es)

                            if sm <= 59 and em <= 59 and ss <= 59 and es <= 59 then

                                item.kind = "hourtimerange"
                                item.start = sm * 60 + ss
                                item.finish = em * 60 + es

                            else
                                message("Ошибка @ времени: " .. timePart)
                            end

                        else
                            message("Ошибка формата @ диапазона: " .. timePart)
                        end

                    end

                else
                    local m, s = value:match("^(%d+):(%d+)$")
                    if m and s then

                        m = tonumber(m)
                        s = tonumber(s)
                        if m <= 59 and s <= 59 then

                            item.kind = "hourtime"
                            item.minute = m
                            item.second = s

                            item.time = m * 60 + s

                        else
                            message("Ошибка @ времени: " .. timePart)
                        end

                    else
                        local m = tonumber(value)
                        if m and m <= 59 then

                            item.kind = "hourminute"
                            item.minute = m

                        else
                            message("Ошибка @ времени: " .. timePart)
                        end

                    end
                end

            elseif timePart:find(":") then
                if timePart:find("-") then
                    local sh, sm, ss, eh, em, es = timePart:match("^(%d+):(%d+):?(%d*)%-(%d+):(%d+):?(%d*)$")
                    if sh then

                        ss = ss ~= "" and tonumber(ss) or 0
                        es = es ~= "" and tonumber(es) or 59

                        sh = tonumber(sh)
                        sm = tonumber(sm)
                        eh = tonumber(eh)
                        em = tonumber(em)

                        if sh <= 23 and eh <= 23
                            and sm <= 59 and em <= 59
                            and ss <= 59 and es <= 59 then

                            item.kind = "timerange"
                            item.start =
                                sh * 3600 +
                                sm * 60 +
                                ss
                            item.finish =
                                eh * 3600 +
                                em * 60 +
                                es

                        else
                            message("Ошибка времени: " .. timePart)
                        end

                    else
                        message("Ошибка диапазона времени: " .. timePart)
                    end

                else

                    local h, m, s = timePart:match("^(%d+):(%d+):?(%d*)$")
                    if h then

                        h = tonumber(h)
                        m = tonumber(m)

                        item.kind = "time"
                        item.hasSeconds =
                            s ~= ""

                        s =
                            item.hasSeconds
                            and tonumber(s)
                            or 0

                        if h <= 23
                            and m <= 59
                            and s <= 59 then

                            item.time =
                                h * 3600 +
                                m * 60 +
                                s

                        else
                            message("Ошибка времени: " .. timePart)
                        end

                    else
                        message("Ошибка времени: " .. timePart)
                    end
                end

            else

                local a, b = timePart:match("^(%d+)%-(%d+)$")
                if a then

                    a = tonumber(a)
                    b = tonumber(b)

                    if a <= 59 and b <= 59 then

                        item.kind = "minuterange"

                        item.startMinute = a
                        item.finishMinute = b

                    else
                        message("Ошибка диапазона минут: " .. timePart)
                    end

                else

                    local m = tonumber(timePart)
                    if m and m <= 59 then

                        item.kind = "minute"
                        item.minute = m

                    else
                        message("Ошибка минуты: " .. timePart)
                    end

                end
            end

            if item.kind then
                schedule[#schedule + 1] = item
            end

            ::continue::
        end

        return schedule
    end

    function checkMSKTimeAdvanced(timeStr, defaultMode)
        local now = os.time(os.date("!*t")) + 3 * 3600
        if now ~= cachedStamp then

            cachedStamp = now
            local t = os.date("*t", now)
            cachedSecondOfDay =
                t.hour * 3600 +
                t.min * 60 +
                t.sec

            cachedMinute = t.min
            cachedSecond = t.sec
        end

        local cacheKey = tostring(timeStr) .. "|" .. tostring(defaultMode or "")
        local schedule = parsedCache[cacheKey]
        if not schedule then
            schedule = compileSchedule(timeStr, defaultMode)
            parsedCache[cacheKey] = schedule
        end

        for i = 1, #schedule do

            local item = schedule[i]
            local matched = false
            if item.kind == "hourtime" then

                local currentHourSecond = cachedMinute * 60 + cachedSecond
                matched = currentHourSecond == item.time

            elseif item.kind == "hourminute" then
                matched = cachedMinute == item.minute

            elseif item.kind == "hourtimerange" then

                local currentHourSecond = cachedMinute * 60 + cachedSecond
                if item.start <= item.finish then
                    matched = currentHourSecond >= item.start and currentHourSecond <= item.finish

                else
                    matched = currentHourSecond >= item.start or currentHourSecond <= item.finish

                end

            elseif item.kind == "timerange" then
                if item.start <= item.finish then
                    matched =cachedSecondOfDay >= item.start and cachedSecondOfDay <= item.finish

                else
                    matched = cachedSecondOfDay >= item.start or cachedSecondOfDay <= item.finish

                end

            elseif item.kind == "time" then
                if item.hasSeconds then
                    matched = cachedSecondOfDay == item.time

                else
                    matched = cachedSecondOfDay >= item.time and cachedSecondOfDay < item.time + 60

                end

            elseif item.kind == "minute" then
                matched = cachedMinute == item.minute

            elseif item.kind == "minuterange" then
                if item.startMinute <= item.finishMinute then
                    matched = cachedMinute >= item.startMinute and cachedMinute <= item.finishMinute

                else
                    matched = cachedMinute >= item.startMinute or cachedMinute <= item.finishMinute

                end
            end

            if item.mode == "loop" then
                if matched then return true end

            else
                if matched then
                    if not timeState[item.key] then
                        timeState[item.key] = true
                        return true
                    end
                else
                    timeState[item.key] = false
                end
            end
        end

        return false
    end
end

function getMSKTime()
    local utc = os.time(os.date("!*t"))      -- UTC
    local msk = utc + 3 * 3600                -- UTC+3 (МСК)
    return os.date("%H:%M", msk)
end

function theme() -- Стиль mimgui
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4
    local ImVec2 = imgui.ImVec2

    style.WindowPadding = imgui.ImVec2(8, 8)
    style.WindowRounding = 6
    style.ChildRounding = 5
    style.FramePadding = imgui.ImVec2(5, 3)
    style.FrameRounding = 3.0
    style.ItemSpacing = imgui.ImVec2(5, 4)
    style.ItemInnerSpacing = imgui.ImVec2(4, 4)
    style.IndentSpacing = 21
    style.ScrollbarSize = 10.0
    style.ScrollbarRounding = 13
    style.GrabMinSize = 8
    style.GrabRounding = 1
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

    colors[clr.Text]                   = ImVec4(0.95, 0.96, 0.98, 1.00);
    colors[clr.TextDisabled]           = ImVec4(0.29, 0.29, 0.29, 1.00);
    colors[clr.WindowBg]               = ImVec4(0.14, 0.14, 0.14, 1.00);
    colors[clr.ChildBg]                = ImVec4(0.12, 0.12, 0.12, 1.00);
    colors[clr.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94);
    colors[clr.Border]                 = ImVec4(0.14, 0.14, 0.14, 1.00);
    colors[clr.BorderShadow]           = ImVec4(1.00, 1.00, 1.00, 0.10);
    colors[clr.FrameBg]                = ImVec4(0.22, 0.22, 0.22, 1.00);
    colors[clr.FrameBgHovered]         = ImVec4(0.18, 0.18, 0.18, 1.00);
    colors[clr.FrameBgActive]          = ImVec4(0.09, 0.12, 0.14, 1.00);
    colors[clr.TitleBg]                = ImVec4(0.14, 0.14, 0.14, 0.81);
    colors[clr.TitleBgActive]          = ImVec4(0.14, 0.14, 0.14, 1.00);
    colors[clr.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.51);
    colors[clr.MenuBarBg]              = ImVec4(0.20, 0.20, 0.20, 1.00);
    colors[clr.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.39);
    colors[clr.ScrollbarGrab]          = ImVec4(0.36, 0.36, 0.36, 1.00);
    colors[clr.ScrollbarGrabHovered]   = ImVec4(0.18, 0.22, 0.25, 1.00);
    colors[clr.ScrollbarGrabActive]    = ImVec4(0.24, 0.24, 0.24, 1.00);
    colors[clr.CheckMark]              = ImVec4(1.00, 0.28, 0.28, 1.00);
    colors[clr.SliderGrab]             = ImVec4(1.00, 0.28, 0.28, 1.00);
    colors[clr.SliderGrabActive]       = ImVec4(1.00, 0.28, 0.28, 1.00);
    colors[clr.Button]                 = ImVec4(0.76, 0.16, 0.16, 1.00);
    colors[clr.ButtonHovered]          = ImVec4(1.00, 0.39, 0.39, 1.00);
    colors[clr.ButtonActive]           = ImVec4(1.00, 0.21, 0.21, 1.00);
    colors[clr.Header]                 = ImVec4(1.00, 0.28, 0.28, 1.00);
    colors[clr.HeaderHovered]          = ImVec4(1.00, 0.39, 0.39, 1.00);
    colors[clr.HeaderActive]           = ImVec4(1.00, 0.21, 0.21, 1.00);
    colors[clr.ResizeGrip]             = ImVec4(1.00, 0.28, 0.28, 1.00);
    colors[clr.ResizeGripHovered]      = ImVec4(1.00, 0.39, 0.39, 1.00);
    colors[clr.ResizeGripActive]       = ImVec4(1.00, 0.19, 0.19, 1.00);
    colors[clr.Tab]                    = ImVec4(0.09, 0.09, 0.09, 1.00);
    colors[clr.TabHovered]             = ImVec4(0.58, 0.23, 0.23, 1.00);
    colors[clr.TabActive]              = ImVec4(0.76, 0.16, 0.16, 1.00);
    colors[clr.Button]                 = ImVec4(0.40, 0.39, 0.38, 0.16);
    colors[clr.ButtonHovered]          = ImVec4(0.40, 0.39, 0.38, 0.39);
    colors[clr.ButtonActive]           = ImVec4(0.40, 0.39, 0.38, 1.00);
    colors[clr.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00);
    colors[clr.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00);
    colors[clr.PlotHistogram]          = ImVec4(1.00, 0.21, 0.21, 1.00);
    colors[clr.PlotHistogramHovered]   = ImVec4(1.00, 0.18, 0.18, 1.00);
    colors[clr.TextSelectedBg]         = ImVec4(1.00, 0.32, 0.32, 1.00);
    colors[clr.ModalWindowDimBg]   = ImVec4(0.26, 0.26, 0.26, 0.60);
end