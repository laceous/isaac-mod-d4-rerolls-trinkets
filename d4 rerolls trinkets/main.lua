local mod = RegisterMod('D4 Rerolls Trinkets', 1)
local json = require('json')
local game = Game()

mod.taintedEdenTrinkets = {}
mod.rngShiftIdx = 35

mod.state = {}
mod.state.rollSlottedTrinkets = true
mod.state.rollSmeltedTrinkets = true
mod.state.keepGoldTrinketStatus = false

function mod:onGameStart()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      for _, v in ipairs({ 'rollSlottedTrinkets', 'rollSmeltedTrinkets', 'keepGoldTrinketStatus' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
    end
  end
end

function mod:onGameExit()
  mod:save()
  mod:clearTaintedEdenTrinkets()
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

-- filtered to COLLECTIBLE_D4 (includes D100, etc)
function mod:onUseItem(collectible, rng, player, useFlags, activeSlot, varData)
  mod:rerollTrinkets(player, rng, false)
end

-- filtered to ENTITY_PLAYER
function mod:onEntityTakeDmg(entity, amount, dmgFlags, source, countdown)
  local player = entity:ToPlayer()
  
  if player:GetPlayerType() == PlayerType.PLAYER_EDEN_B and not mod:hasAnyFlag(dmgFlags, DamageFlag.DAMAGE_FAKE | DamageFlag.DAMAGE_NO_PENALTIES) then
    local rng = RNG()
    rng:SetSeed(player.InitSeed, mod.rngShiftIdx)
    mod:rerollTrinkets(player, rng, true)
  end
end

-- filtered to 0-Player
function mod:onPlayerUpdate(player)
  if player:GetPlayerType() == PlayerType.PLAYER_EDEN_B then
    local playerHash = GetPtrHash(player)
    
    -- overwrite new tainted eden trinkets with our choices
    if mod.taintedEdenTrinkets[playerHash] then
      local slottedTrinkets = {}
      
      do
        local slot = 0
        local trinket = player:GetTrinket(slot)
        
        while trinket ~= TrinketType.TRINKET_NULL do
          player:TryRemoveTrinket(trinket)
          table.insert(slottedTrinkets, trinket)
          
          trinket = player:GetTrinket(slot)
        end
      end
      
      for i, trinket in ipairs(slottedTrinkets) do
        if mod.state.keepGoldTrinketStatus and mod.taintedEdenTrinkets[playerHash][i] then
          -- sync gold status for the game's selected trinket
          local isGoldTrinket = mod.taintedEdenTrinkets[playerHash][i] > TrinketType.TRINKET_GOLDEN_FLAG
          trinket = isGoldTrinket and trinket | TrinketType.TRINKET_GOLDEN_FLAG or trinket & ~TrinketType.TRINKET_GOLDEN_FLAG
        end
        
        player:AddTrinket(trinket, false)
      end
      
      mod.taintedEdenTrinkets[playerHash] = nil
    end
  end
end

function mod:rerollTrinkets(player, rng, isTaintedEden)
  local itemPool = game:GetItemPool()
  local playerHash = GetPtrHash(player)
  local slottedTrinkets = {}
  local smeltedTrinkets = {}
  
  -- trinkets auto-organize themselves
  -- you can't have a trinket in slot 1 if slot 0 is empty
  -- loop to potentially future proof this if more slots are ever added
  do
    local slot = 0
    local trinket = player:GetTrinket(slot)
    
    while trinket ~= TrinketType.TRINKET_NULL do
      player:TryRemoveTrinket(trinket) -- removes slotted trinkets before smelted trinkets
      table.insert(slottedTrinkets, trinket)
      
      trinket = player:GetTrinket(slot)
    end
  end
  
  -- additional tainted eden birthright behavior: smelted trinkets are no longer re-rolled
  -- not sure it's possible to 100% support only smelted trinkets obtained before birthright
  if mod.state.rollSmeltedTrinkets and not mod:isTaintedEdenBirthright(player) then
    for _, trinket in ipairs(mod:getTrinkets()) do -- all non-gold trinket IDs
      for _, trinket in ipairs({ trinket + TrinketType.TRINKET_GOLDEN_FLAG, trinket }) do -- check gold first
        local trinketRemoved = nil
        
        -- HasTrinket doesn't differentiate between gold and non-gold trinkets
        while trinketRemoved ~= false and player:HasTrinket(trinket, false) do -- false for smelted trinkets
          -- will remove gold or non-gold trinkets when passed non-gold ID
          -- will only remove gold trinkets when passed gold ID
          trinketRemoved = player:TryRemoveTrinket(trinket)
          
          -- check in case this is something we can't remove
          if trinketRemoved then
            table.insert(smeltedTrinkets, trinket)
          end
        end
      end
    end
  end
  
  for _, trinket in ipairs(smeltedTrinkets) do
    local isGoldTrinket = trinket > TrinketType.TRINKET_GOLDEN_FLAG
    trinket = itemPool:GetTrinket(false) -- could be gold or non-gold
    
    if mod.state.keepGoldTrinketStatus then
      trinket = isGoldTrinket and trinket | TrinketType.TRINKET_GOLDEN_FLAG or trinket & ~TrinketType.TRINKET_GOLDEN_FLAG
    end
    
    player:AddTrinket(trinket, false) -- rolled trinkets don't give pickups
    player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, false, false, true, false, -1, 0)
  end
  
  if isTaintedEden and mod.state.keepGoldTrinketStatus then
    mod.taintedEdenTrinkets[playerHash] = {}
  end
  
  for _, trinket in ipairs(slottedTrinkets) do
    if not isTaintedEden and mod.state.rollSlottedTrinkets then
      local isGoldTrinket = trinket > TrinketType.TRINKET_GOLDEN_FLAG
      trinket = itemPool:GetTrinket(false)
      
      if mod.state.keepGoldTrinketStatus then
        trinket = isGoldTrinket and trinket | TrinketType.TRINKET_GOLDEN_FLAG or trinket & ~TrinketType.TRINKET_GOLDEN_FLAG
      end
    end
    
    player:AddTrinket(trinket, false)
    
    if isTaintedEden and mod.state.keepGoldTrinketStatus then
      table.insert(mod.taintedEdenTrinkets[playerHash], trinket)
    end
  end
end

function mod:getTrinkets()
  local itemConfig = Isaac.GetItemConfig()
  local trinkets = {}
  
  -- 0 is TrinketType.TRINKET_NULL
  for i = 1, #itemConfig:GetTrinkets() - 1 do
    local trinketConfig = itemConfig:GetTrinket(i)
    
    if trinketConfig then
      table.insert(trinkets, trinketConfig.ID)
    end
  end
  
  return trinkets
end

function mod:hasTaintedEden()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    if player:GetPlayerType() == PlayerType.PLAYER_EDEN_B then
      return true
    end
  end
  
  return false
end

function mod:isTaintedEdenBirthright(player)
  return player:GetPlayerType() == PlayerType.PLAYER_EDEN_B and
         player:HasCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, false)
end

function mod:hasAnyFlag(flags, flag)
  return flags & flag ~= 0
end

function mod:clearTaintedEdenTrinkets()
  for k, _ in pairs(mod.taintedEdenTrinkets) do
    mod.taintedEdenTrinkets[k] = nil
  end
end

function mod:setupEid()
  EID:addDescriptionModifier(mod.Name .. ' - D4', function(descObj)
    return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE and descObj.ObjSubType == CollectibleType.COLLECTIBLE_D4
  end, function(descObj)
    -- english only for now
    EID:appendToDescription(descObj, '#Reroll all of Isaac\'s trinkets (including smelted trinkets)')
    return descObj
  end)
  
  EID:addDescriptionModifier(mod.Name .. ' - Birthright', function(descObj)
    return descObj.ObjType == EntityType.ENTITY_PICKUP and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE and descObj.ObjSubType == CollectibleType.COLLECTIBLE_BIRTHRIGHT and
           mod:hasTaintedEden()
  end, function(descObj)
    EID:appendToDescription(descObj, '#{{Player30}} Smelted trinkets can no longer be rerolled')
    return descObj
  end)
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Settings' }) do
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
  for _, v in ipairs({
                      { field = 'rollSlottedTrinkets', adjective = 'slotted', info = { 'Reroll trinkets in either of the first two slots?' } },
                      { field = 'rollSmeltedTrinkets', adjective = 'smelted', info = { 'Reroll trinkets that have been smelted/gulped?' } },
                    })
  do
    ModConfigMenu.AddSetting(
      mod.Name,
      'Settings',
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.field]
        end,
        Display = function()
          return 'Reroll ' .. v.adjective .. ' trinkets: ' .. (mod.state[v.field] and 'on' or 'off')
        end,
        OnChange = function(b)
          mod.state[v.field] = b
          mod:save()
        end,
        Info = v.info
      }
    )
  end
  ModConfigMenu.AddSpace(mod.Name, 'Settings')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.keepGoldTrinketStatus
      end,
      Display = function()
        return 'Golden trinkets: ' .. (mod.state.keepGoldTrinketStatus and 'keep status' or 'random')
      end,
      OnChange = function(b)
        mod.state.keepGoldTrinketStatus = b
        mod:save()
      end,
      Info = { 'Random: gold can reroll into non-gold', 'Keep status: gold will always reroll into gold', '(and vice versa)' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_D4)
mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDmg, EntityType.ENTITY_PLAYER) -- let other mods "return false"
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.onPlayerUpdate, 0) -- 0 is player, 1 is co-op baby

if EID then
  mod:setupEid()
end
if ModConfigMenu then
  mod:setupModConfigMenu()
end