local mod = RegisterMod('D4 Rerolls Trinkets', 1)
local game = Game()

mod.rngShiftIdx = 35

-- filtered to COLLECTIBLE_D4 (includes D100, etc)
function mod:onUseItem(collectible, rng, player, useFlags, activeSlot, varData)
  mod:rerollTrinkets(player, rng)
end

--filtered to ENTITY_PLAYER
function mod:onEntityTakeDmg(entity, amount, dmgFlags, source, countdown)
  local player = entity:ToPlayer()
  
  -- no birthright support for now
  if player:GetPlayerType() == PlayerType.PLAYER_EDEN_B and not mod:hasAnyFlag(dmgFlags, DamageFlag.DAMAGE_FAKE | DamageFlag.DAMAGE_NO_PENALTIES) then
    local rng = RNG()
    rng:SetSeed(player.InitSeed, mod.rngShiftIdx)
    mod:rerollTrinkets(player, rng)
  end
end

function mod:rerollTrinkets(player, rng)
  local itemPool = game:GetItemPool()
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
  
  -- treat golden trinkets the same as non-golden trinkets (all trinkets count as +1)
  for _, trinket in ipairs(mod:getTrinkets()) do
    local trinketRemoved = nil
    
    while trinketRemoved ~= false and player:HasTrinket(trinket, false) do -- false for smelted trinkets
      if player:TryRemoveTrinket(trinket) then -- check in case this is something we can't remove
        table.insert(smeltedTrinkets, trinket)
        trinketRemoved = true
      else
        trinketRemoved = false
      end
    end
  end
  
  for _ in ipairs(smeltedTrinkets) do
    local trinket = itemPool:GetTrinket(false)
    player:AddTrinket(trinket, false) -- rolled passive items don't give pickups
    player:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, false, false, true, false, -1, 0)
  end
  
  for _ in ipairs(slottedTrinkets) do
    local trinket = itemPool:GetTrinket(false)
    player:AddTrinket(trinket, true) -- slotted trinkets should give pickups
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

function mod:hasAnyFlag(flags, flag)
  return flags & flag ~= 0
end

mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.onUseItem, CollectibleType.COLLECTIBLE_D4)
mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDmg, EntityType.ENTITY_PLAYER) -- let other mods "return false"