-----------------------------------------------------------------------------------------------
-- Client Lua Script for VikingHealthShieldBar
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
require "Window"
require "Apollo"
require "GameLib"
require "Spell"
require "Unit"
require "Item"

local VikingHealthShieldBar = {}

function VikingHealthShieldBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function VikingHealthShieldBar:Init()
    Apollo.RegisterAddon(self)
end

local knEvadeResource = 7 -- the resource hooked to dodges (TODO replace with enum)

local eEnduranceFlash =
{
  EnduranceFlashZero = 1,
  EnduranceFlashOne = 2,
  EnduranceFlashTwo = 3,
  EnduranceFlashThree = 4,
}

function VikingHealthShieldBar:OnLoad() -- OnLoad then GetAsyncLoad then OnRestore
  self.xmlDoc = XmlDoc.CreateFromFile("VikingHealthShieldBar.xml")
  Apollo.RegisterEventHandler("InterfaceOptionsLoaded", "OnDocumentReady", self)
  self.xmlDoc:RegisterCallback("OnDocumentReady", self)

  Apollo.LoadSprites("VikingHealthShieldBarSprites.xml")
end

function VikingHealthShieldBar:OnDocumentReady()
  if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() or not g_InterfaceOptionsLoaded or self.wndMain then
    return
  end
  Apollo.RegisterEventHandler("Tutorial_RequestUIAnchor",       "OnTutorial_RequestUIAnchor", self)
  Apollo.RegisterEventHandler("UnitEnteredCombat",          "OnEnteredCombat", self)
  Apollo.RegisterEventHandler("RefreshVikingHealthShieldBar",         "OnFrameUpdate", self)

  Apollo.RegisterTimerHandler("HealthShieldBarTimer",         "OnFrameUpdate", self)
  Apollo.RegisterTimerHandler("EnduranceDisplayTimer",        "OnEnduranceDisplayTimer", self)

  Apollo.CreateTimer("HealthShieldBarTimer", 0.5, true)
  --Apollo.CreateTimer("EnduranceDisplayTimer", 30, false) --TODO: Fix(?) This is perma-killing the display when DT dashing is disabled via the toggle

    self.wndMain = Apollo.LoadForm(self.xmlDoc, "VikingHealthShieldBarForm", "FixedHudStratum", self)

  self.wndEndurance = self.wndMain:FindChild("EnduranceContainer")
  -- self.wndDisableDash = self.wndEndurance:FindChild("DisableDashToggleContainer")

  self.bInCombat = false
  self.eEnduranceState = eEnduranceFlash.EnduranceFlashZero
  self.bEnduranceFadeTimer = false

  -- For flashes
  self.nLastEnduranceValue = 0

  -- todo: make this selective
  self.wndEndurance:Show(false, true)

  self.xmlDoc = nil
  self:OnFrameUpdate()
end

function VikingHealthShieldBar:OnFrameUpdate()
  local unitPlayer = GameLib.GetPlayerUnit()
  if unitPlayer == nil then
    return
  end

  -- Evades
  local nEvadeCurr = unitPlayer:GetResource(knEvadeResource)
  local nEvadeMax = unitPlayer:GetMaxResource(knEvadeResource)
  self:UpdateEvades(nEvadeCurr, nEvadeMax)

  -- Evade Blocker
  -- TODO: Store this and only update when needed
  local bShowDoubleTapToDash = Apollo.GetConsoleVariable("player.showDoubleTapToDash")
  local bSettingDoubleTapToDash = Apollo.GetConsoleVariable("player.doubleTapToDash")

  -- self.wndDisableDash:Show(bShowDoubleTapToDash)
  self.wndEndurance:FindChild("EvadeFlashSprite"):Show(bShowDoubleTapToDash and bSettingDoubleTapToDash)
  self.wndEndurance:FindChild("EvadeDisabledBlocker"):Show(bShowDoubleTapToDash and not bSettingDoubleTapToDash)
  -- self.wndDisableDash:FindChild("DisableDashToggleFlash"):Show(bShowDoubleTapToDash and not bSettingDoubleTapToDash)
  -- self.wndDisableDash:FindChild("DisableDashToggle"):SetCheck(bShowDoubleTapToDash and not bSettingDoubleTapToDash)
  -- self.wndDisableDash:SetTooltip(bSettingDoubleTapToDash and Apollo.GetString("HealthBar_DisableDoubleTapEvades") or Apollo.GetString("HealthBar_EnableDoubletapTooltip"))

  -- Show/Hide EnduranceEvade UI
  if self.bInCombat or nRunCurr ~= nRunMax or nEvadeCurr ~= nEvadeMax or bShowDoubleTapToDash then
    Apollo.StopTimer("EnduranceDisplayTimer")
    self.bEnduranceFadeTimer = false
    self.wndEndurance:Show(true, true)
  elseif not self.bEnduranceFadeTimer then
    Apollo.StopTimer("EnduranceDisplayTimer")
    Apollo.StartTimer("EnduranceDisplayTimer")
    self.bEnduranceFadeTimer = true
  end

  --Toggle Visibility based on ui preference
  local unitPlayer = GameLib.GetPlayerUnit()
  local nVisibility = Apollo.GetConsoleVariable("hud.skillsBarDisplay")

  if nVisibility == 1 then --always on
    self.wndMain:Show(true)
  elseif nVisibility == 2 then --always off
    self.wndMain:Show(false)
  elseif nVisibility == 3 then --on in combat
    self.wndMain:Show(unitPlayer:IsInCombat())
  elseif nVisibility == 4 then --on out of combat
    self.wndMain:Show(not unitPlayer:IsInCombat())
  else
    self.wndMain:Show(false)
  end

  --hide evade UI while in a vehicle.
  if unitPlayer:IsInVehicle() then
    self.wndMain:Show(false)
  end
end

function VikingHealthShieldBar:UpdateEvades(nEvadeValue, nEvadeMax)
  local strSpriteFull = "spr_HUD_Dodge2"
  local nMaxTick = math.floor(nEvadeMax/100)
  local nMaxState = eEnduranceFlash.EnduranceFlashTwo

  local nEvadeCurr = math.floor(nEvadeValue/100) * 100
  self.wndEndurance:FindChild("EvadeProgress"):SetMax(nEvadeMax)
  self.wndEndurance:FindChild("EvadeProgress"):SetProgress(nEvadeCurr)


  local nTickValue = nEvadeValue % 100 == 0 and 100 or nEvadeValue % 100
  self.wndEndurance:FindChild("EvadeReloadProgress"):SetMax(100)
  self.wndEndurance:FindChild("EvadeReloadProgress"):SetProgress(nTickValue)

  local wndMarkers = {}
  local tPos = {
    nLeft  = 0,
    nTop   = 0,
    nRight = 16,
    nBottom  = 16
  }

  tPos.nFrameLeft, tPos.nFrameTop, tPos.nFrameRight, tPos.nFrameBottom = self.wndEndurance:GetAnchorOffsets()
  local nMaxWidth = math.abs(tPos.nFrameLeft - tPos.nFrameRight)
  local nDividerOffset = math.ceil(nMaxWidth/nMaxTick)

  for i = 1, nMaxTick do

    wndMarkers[i] = self.wndEndurance:FindChild("Marker" .. i)
    wndMarkers[i]:Show(true)
    local nStart = nDividerOffset/nMaxTick * -1
    if i == 1 then
      nStart = nDividerOffset/nMaxTick
    elseif i == nMaxTick then
      nStart = nDividerOffset/nMaxTick * -1
    end
    wndMarkers[i]:SetAnchorOffsets(nStart + tPos.nLeft + nDividerOffset*(i-1), tPos.nTop, nStart + tPos.nRight + nDividerOffset*(i-1), tPos.nBottom)
  end

  local wndDivider1 = self.wndEndurance:FindChild("Divider1")
  local wndDivider2 = self.wndEndurance:FindChild("Divider2")

  local strEvadeTooltop = Apollo.GetString(Apollo.GetConsoleVariable("player.doubleTapToDash") and "HealthBar_EvadeDoubleTapTooltip" or "HealthBar_EvadeKeyTooltip")
  local strDisplayTooltip = String_GetWeaselString(strEvadeTooltop, math.floor(nEvadeValue / 100), math.floor(nEvadeMax / 100))
  self.wndEndurance:FindChild("EvadeFullSprite"):SetTooltip(strDisplayTooltip)

  self.nLastEnduranceValue = nEvadeValue
end

function VikingHealthShieldBar:OnEnteredCombat(unit, bInCombat)
  if unit == GameLib.GetPlayerUnit() then
    self.bInCombat = bInCombat
  end
end

function VikingHealthShieldBar:OnEnduranceDisplayTimer()
  self.bEnduranceFadeTimer = false
  self.wndEndurance:Show(false)
end

function VikingHealthShieldBar:OnMouseButtonDown(wnd, wndControl, iButton, nX, nY, bDouble)
  if iButton == 0 then -- Left Click
    GameLib.SetTargetUnit(GameLib.GetPlayerUnit())
  end
  return true -- stop propogation
end

function VikingHealthShieldBar:OnDisableDashToggle(wndHandler, wndControl)
  Apollo.SetConsoleVariable("player.doubleTapToDash", not wndControl:IsChecked())
  self.wndEndurance:FindChild("EvadeDisabledBlocker"):Show(not wndControl:IsChecked())
  self.wndEndurance:FindChild("EvadeProgress"):Show(not wndControl:IsChecked())
  -- self.wndDisableDash:FindChild("DisableDashToggleFlash"):Show(not wndControl:IsChecked())
  self:OnFrameUpdate()
end

function VikingHealthShieldBar:OnTutorial_RequestUIAnchor(eAnchor, idTutorial, strPopupText)
  if eAnchor == GameLib.CodeEnumTutorialAnchor.DashMeter then
    local tRect = {}
    tRect.l, tRect.t, tRect.r, tRect.b = self.wndMain:GetRect()
    Event_FireGenericEvent("Tutorial_RequestUIAnchorResponse", eAnchor, idTutorial, strPopupText, tRect)
  elseif eAnchor == GameLib.CodeEnumTutorialAnchor.ClassResource then
    local tRect = {}
    tRect.l, tRect.t, tRect.r, tRect.b = self.wndMain:GetRect()
    Event_FireGenericEvent("Tutorial_RequestUIAnchorResponse", eAnchor, idTutorial, strPopupText, tRect)
  elseif eAnchor == GameLib.CodeEnumTutorialAnchor.HealthBar then
    local tRect = {}
    tRect.l, tRect.t, tRect.r, tRect.b = self.wndMain:GetRect()
    Event_FireGenericEvent("Tutorial_RequestUIAnchorResponse", eAnchor, idTutorial, strPopupText, tRect)
  elseif eAnchor == GameLib.CodeEnumTutorialAnchor.ShieldBar then
    local tRect = {}
    tRect.l, tRect.t, tRect.r, tRect.b = self.wndMain:GetRect()
    Event_FireGenericEvent("Tutorial_RequestUIAnchorResponse", eAnchor, idTutorial, strPopupText, tRect)
  end
end

local VikingHealthShieldBarInst = VikingHealthShieldBar:new()
VikingHealthShieldBarInst:Init()
