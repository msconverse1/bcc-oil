-----------------------------------------Pulling Essentials-------------------------------------------------------------------------
local VORPcore = exports.vorp_core:GetCore() -- NEW includes  new callback system
local BccUtils = exports['bcc-utils'].initiate()
local discord = BccUtils.Discord.setup(Config.WebhookLink, 'BCC Oil', 'https://gamespot.com/a/uploads/original/1179/11799911/3383938-duck.jpg')

--------- Oil Mission Payout Handler -------------
RegisterServerEvent('bcc:oil:PayoutOilMission', function(wagonModel)
  local _source = source
  local user = VORPcore.getUser(_source)
  if not user then return end
  local Character = user.getUsedCharacter
  local param = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier, ['levelincrease'] = Config.LevelIncreasePerDelivery }
  MySQL.query.await('UPDATE oil SET `manager_trust`=manager_trust+@levelincrease WHERE charidentifier=@charidentifier AND identifier=@identifier', param)
  local result = MySQL.query.await("SELECT manager_trust FROM oil WHERE charidentifier=@charidentifier AND identifier=@identifier", param)
  if #result > 0 then
    for k, v in pairs(Config.OilCompanyLevels) do
      if result[1].manager_trust >= v.level and result[1].manager_trust < v.nextlevel then
        if wagonModel == 'oilwagon02x' then
          Character.addCurrency(0, Config.BasicOilDeliveryPay + v.payoutbonus) break
        elseif wagonModel == 'armysupplywagon' then
          Character.addCurrency(0, Config.SupplyDeliveryBasePay + v.payoutbonus) break
        end
      elseif result[1].manager_trust < v.level then
        if wagonModel == 'oilwagon02x' then
          Character.addCurrency(0, Config.BasicOilDeliveryPay) break
        elseif wagonModel == 'armysupplywagon' then
          Character.addCurrency(0, Config.SupplyDeliveryBasePay) break
        end
      end
    end
  end
end)

-------- Robbery Payout Handler --------
RegisterServerEvent('bcc-oil:RobberyPayout', function()
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then return end
    local Character = user.getUsedCharacter
    local result = MySQL.query.await('SELECT manager_trust, enemy_trust FROM oil WHERE charidentifier = ? AND identifier = ?',
        { Character.charIdentifier, Character.identifier })

    if result then
        local managerTrust = result[1].manager_trust
        local enemyTrust = result[1].enemy_trust
        local levelDecrease = Config.OilCompanyLevelDecrease
        local newManagerTrust = managerTrust
        if managerTrust >= levelDecrease then
            newManagerTrust = managerTrust - levelDecrease
        end
        local newEnemyTrust = enemyTrust + Config.LevelIncreasePerDelivery
        MySQL.query.await('UPDATE oil SET manager_trust = ?, enemy_trust = ? WHERE charidentifier = ? AND identifier = ?',
            { newManagerTrust, newEnemyTrust, Character.charIdentifier, Character.identifier })

        for _, v in pairs(Config.CriminalLevels) do
            if enemyTrust >= v.level and enemyTrust < v.nextlevel then
                Character.addCurrency(0, Config.StealOilWagonBasePay + v.payoutbonus)
                break
            elseif enemyTrust < v.level then
                Character.addCurrency(0, Config.StealOilWagonBasePay)
                break
            end
        end
    end
end)

--Cooldown Event
local wagonrobcooldown, oilcorobcooldown = false, false
RegisterServerEvent('bcc-oil:CrimCooldowns', function(missiontype)
  local _source = source
  local user = VORPcore.getUser(_source)
  if not user then return end
  local Character = user.getUsedCharacter
  if missiontype == 'wagonrob' then
    if not wagonrobcooldown then
      TriggerClientEvent('bcc-oil:RobOilWagon', _source)
      discord:sendMessage(_U('RobberyTitle'), _U('Robbery_desc2') .. tostring(Character.charIdentifier))
      wagonrobcooldown = true
      Wait(Config.RobOilWagonCooldown)
      wagonrobcooldown = false
    else
      VORPcore.NotifyRightTip(_source, _U('Cooldown'), 4000)
    end
  elseif missiontype == 'corob' then
    if not oilcorobcooldown then
      TriggerClientEvent('bcc-oil:RobOilCo', _source)
      discord:sendMessage(_U('RobberyTitle'), _U('Robbery_desc') .. tostring(Character.charIdentifier))
      oilcorobcooldown = true
      Wait(Config.RobOilCoCooldown)
      oilcorobcooldown = false
    else
      VORPcore.NotifyRightTip(_source, _U('Cooldown'), 4000)
    end
  end
end)

RegisterServerEvent('bcc-oil:OilCoRobberyPayout', function(fillcoords2)
  local _source = source
  local user = VORPcore.getUser(_source)
  if not user then return end
  local Character = user.getUsedCharacter
  if fillcoords2.rewards.itemspayout then
    for k, v in pairs(fillcoords2.rewards.items) do
      exports.vorp_inventory:addItem(_source, v.item, v.count)
      VORPcore.NotifyRightTip(_source, _U('You have Stolen Items'), 4000)
      Character.addCurrency(0, fillcoords2.rewards.cashpayout)
    end
  else
    Character.addCurrency(0, fillcoords2.rewards.cashpayout)
  end
end)

------- Checks if player exists in db if not it adds ------
RegisterServerEvent('bcc:oil:DBCheck', function()
  local _source = source
  local user = VORPcore.getUser(_source)
  if not user then return end
  local Character = user.getUsedCharacter
  local param = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier }
  --------The if you exist in db code was pulled from vorp_banking and modified ----------------
  local result = MySQL.query.await("SELECT identifier, charidentifier FROM oil WHERE identifier = @identifier AND charidentifier = @charidentifier", param)
  if #result <= 0 then
    exports.oxmysql:execute("INSERT INTO oil ( `charidentifier`,`identifier` ) VALUES ( @charidentifier,@identifier )", param)
  end
end)

------------------------------------- Handles the buying, selling, and spawning of wagons ---------------------------------------------
local wagoninspawn = false
RegisterServerEvent('bcc:oil:WagonManagement', function(type, action)
  local _source = source
  local user = VORPcore.getUser(_source)
  if not user then return end
  local Character = user.getUsedCharacter

  if type == 'oilwagon' then
    local param = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier, ['oilwagon'] = 'oilwagon02x' }
    local result = MySQL.query.await("SELECT oil_wagon FROM oil WHERE charidentifier=@charidentifier AND identifier=@identifier", param)
    if #result > 0 then
      if action == 'buy' then
        if result[1].oil_wagon == 'none' then
          if Character.money >= Config.OilWagon.price then
            Character.removeCurrency(0, Config.OilWagon.price)
            discord:sendMessage(_U('BoughtTitle'), _U('bought_desc2') .. tostring(Character.charIdentifier))
            exports.oxmysql:execute("UPDATE oil SET `oil_wagon`=@oilwagon WHERE charidentifier=@charidentifier AND identifier=@identifier", param)
            VORPcore.NotifyRightTip(_source, _U('OilWagonBought'), 4000)
          else
            VORPcore.NotifyRightTip(_source, _U('NotEnoughCash'), 4000)
          end
        else
          VORPcore.NotifyRightTip(_source, _U('OilWagonAlreadyBought'), 4000)
        end
      elseif action == 'sell' then
        if result[1].oil_wagon == 'none' then
          VORPcore.NotifyRightTip(_source, _U('NoWagontoSell'), 4000)
        elseif result[1].oil_wagon == 'oilwagon02x' then
          local param2 = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier, ['oilwagon'] = 'none' }
          exports.oxmysql:execute("UPDATE oil SET `oil_wagon`=@oilwagon WHERE charidentifier=@charidentifier AND identifier=@identifier", param2)
          Character.addCurrency(0, Config.OilWagon.sellprice)
          discord:sendMessage(_U('SoldTitle'), _U('sold_desc') .. tostring(Character.charIdentifier))
          VORPcore.NotifyRightTip(_source, _U('WagonSold'), 4000)
        end
      elseif action == 'spawn' then
        if not wagoninspawn then
          if result[1].oil_wagon == 'none' then
            VORPcore.NotifyRightTip(_source, _U('NoWagonOwned'), 4000)
          elseif result[1].oil_wagon == 'oilwagon02x' then
            discord:sendMessage(_U('DeliveryMissionTitle'), _U('Delivery_desc') .. tostring(Character.charIdentifier))
            wagoninspawn = true
            TriggerClientEvent('bcc:oil:PlayerWagonSpawn', _source, 'oilwagon02x')
          end
        else
          VORPcore.NotifyRightTip(_source, _U('WagonInSpawnLocation'), 4000)
        end
      end
    end
  elseif type == 'supplywagon' then
    local param = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier, ['oilwagon'] = 'armysupplywagon' }
    local result = MySQL.query.await("SELECT delivery_wagon FROM oil WHERE charidentifier=@charidentifier AND identifier=@identifier", param)
    if #result > 0 then
      if action == 'buy' then
        if result[1].delivery_wagon == 'none' then
          if Character.money >= Config.SupplyWagon.price then
            Character.removeCurrency(0, Config.SupplyWagon.price)
            discord:sendMessage(_U('BoughtTitle'), _U('bought_desc') .. tostring(Character.charIdentifier))
            exports.oxmysql:execute("UPDATE oil SET `delivery_wagon`=@oilwagon WHERE charidentifier=@charidentifier AND identifier=@identifier", param)
            VORPcore.NotifyRightTip(_source, _U('SupplyWagonBought'), 4000)
          else
            VORPcore.NotifyRightTip(_source, _U('NotEnoughCash'), 4000)
          end
        else
          VORPcore.NotifyRightTip(_source, _U('SupplyWagonAlreadyBought'), 4000)
        end
      elseif action == 'sell' then
        if result[1].delivery_wagon == 'none' then
          VORPcore.NotifyRightTip(_source, _U('NoWagontoSell'), 4000)
        elseif result[1].delivery_wagon == 'armysupplywagon' then
          local param2 = { ['charidentifier'] = Character.charIdentifier, ['identifier'] = Character.identifier, ['oilwagon'] = 'none' }
          exports.oxmysql:execute("UPDATE oil SET `delivery_wagon`=@oilwagon WHERE charidentifier=@charidentifier AND identifier=@identifier", param2)
          Character.addCurrency(0, Config.SupplyWagon.sellprice)
          discord:sendMessage(_U('SoldTitle'), _U('sold_desc2') .. tostring(Character.charIdentifier))
          VORPcore.NotifyRightTip(_source, _U('WagonSold'), 4000)
        end
      elseif action == 'spawn' then
        if not wagoninspawn then
          if result[1].delivery_wagon == 'none' then
            VORPcore.NotifyRightTip(_source, _U('NoWagonOwned'), 4000)
          elseif result[1].delivery_wagon == 'armysupplywagon' then
            wagoninspawn = true
            discord:sendMessage(_U('DeliveryMissionTitle'), _U('Delivery_desc2') .. tostring(Character.charIdentifier))
            TriggerClientEvent('bcc:oil:PlayerWagonSpawn', _source, 'armysupplywagon')
          end
        else
          VORPcore.NotifyRightTip(_source, _U('WagonInSpawnLocation'), 4000)
        end
      end
    end
  end
end)

--------------Handles making sure the wagon has left the spawn location before allowing a new one to spawn/returend too -------------
RegisterServerEvent('bcc-oil:WagonInSpawnHandler', function(inspawn)
  if inspawn then
    wagoninspawn = true
  else
    wagoninspawn = false
  end
end)

--This handles the version check
BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-oil')
