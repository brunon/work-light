-- This script will control a warning LED to let family members know
-- to not come in during a Zoom meeting

-- Using Zoom spoon from: https://github.com/brunon/Zoom.spoon
-- Forked from: https://github.com/jpf/Zoom.spoon
hs.loadSpoon("Zoom")

-- CitrixViewer spoon from: https://github.com/brunon/CitrixViewer.spoon
hs.loadSpoon("CitrixViewer")

-- Yeelight spoon from: https://github.com/brunon/Yeelight.spoon
hs.loadSpoon("Yeelight")

local inZoomMeeting = false
local isMuted = false
local isVideoOn = false
local isCameraInUse = false
local debug = true
local isScreenLocked = false
local isCitrixRunning = false
local pollingInterval = 2 -- seconds
local ledMode = "off"
local hyperPixelEnabled = true
local hyperPixelSocket = nil
local hyperPixelControlWindow = nil
local hyperPixelDesiredState = false
local hyperPixelConnectTimer = nil
local hyperPixelPingTimer = nil
local chartMonitorSocket = nil
local lights = {}
local ceilingLightID = nil

function _debug(message, ...)
  if debug then
    hs.printf(message, ...)
  end
end

function isWeekend()
  today = os.date("%A")
  if today == "Saturday" or today == "Sunday" then
    _debug("Weekend, keeping LED off")
    return true
  else
    return false
  end
end

function setLightRed()
  spoon.Yeelight:turn_on('FF0000', 75, 'smooth', 5) -- red
  ledMode = "dnd"
end

function setLightAmber()
  spoon.Yeelight:turn_on('FFA500', 75, 'smooth', 5) -- amber
  ledMode = "warning"
end

function setLightGreen()
  spoon.Yeelight:turn_on('008000', 50, 'smooth', 5) -- green
  ledMode = "work"
end

function setLightOff()
  spoon.Yeelight:turn_off()
  ledMode = "off"
end

function updateLightStatus()
  if isScreenLocked or not isCitrixRunning or isWeekend() then
    -- screen is locked, turn off warning LED
    _debug("LED %s => off", ledMode)
    if ledMode ~= "off" then
      setLightOff()
    end
  elseif inZoomMeeting or isCameraInUse then
    if isVideoOn or isCameraInUse then
      _debug("LED %s => dnd", ledMode)
      if ledMode ~= "dnd" then
        setLightRed()
      end
    else
      _debug("LED %s => warning", ledMode)
      if ledMode ~= "warning" then
        setLightAmber()
      end
    end
  else
    _debug("LED %s => work", ledMode)
    if ledMode ~= "work" then
      setLightGreen()
    end
  end
end

function micMuted()
  _debug("Mute ON")
  isMuted = true
  updateLightStatus()
end

function micUnmuted()
  _debug("Mute OFF")
  isMuted = false
  updateLightStatus()
end

function meetingOff()
  _debug("Meeting closed")
  inZoomMeeting = false
  updateLightStatus()
end

function meetingStart()
  _debug("Meeting start")
  if not inZoomMeeting then
    inZoomMeeting = true
    updateLightStatus()
  end
end

function videoOn()
  _debug("Video turned ON")
  isVideoOn = true
  updateLightStatus()
  spoon.Hue:setLightState(ceilingLightID, "true", 50)
end

function videoOff()
  _debug("Video turned OFF")
  isVideoOn = false
  updateLightStatus()
  spoon.Hue:setLightState(ceilingLightID, "true", 200)
end

function hyperPixelSocketCallback(data, tag)
  _debug("Got data from socket: " .. data)
end

function chartMonitorSocketCallback(data, tag)
  _debug("Got data from socket: " .. data)
end

function sendToHyperPixel(command, ...)
  if hyperPixelSocket ~= nil and hyperPixelSocket:connected() then
    message = string.format(command, ...)
    hyperPixelSocket:send(message)
    if message ~= "ping" then
        _debug("Sending to HyperPixel: %s", message)
    end
  end
end

function sendToClusterPiMonitor(command, ...)
  if chartMonitorSocket ~= nil and chartMonitorSocket:connected() then
    message = string.format(command, ...)
    chartMonitorSocket:send(message)
    _debug("Sending to ClusterPi Monitor: %s", message)
  end
end

function turnOnHyperPixel()
  sendToHyperPixel("on")
  sendToClusterPiMonitor("on")
end

function turnOffHyperPixel()
  sendToHyperPixel("off")
  sendToClusterPiMonitor("off")
end

function toggleHyperPixel()
  if hyperPixelDesiredState == true then
    hyperPixelDesiredState = false
    turnOffHyperPixel()
  else
    hyperPixelDesiredState = true
    turnOnHyperPixel()
  end
end

function showHyperPixelControlWindow()
  cw = hs.webview.newBrowser(hs.geometry.rect(1000, 1170, 450, 250))
  cw:windowStyle({"titled", "nonactivating"}):windowTitle("HyperPixel Controls"):url("http://hyperpixel.local/")

  t = require("hs.webview.toolbar")
  a = t.new("HyperPixel Controls", {
          { id = "ON/OFF", image = hs.image.imageFromName("NSWinHighSwitch") },
          { id = "navGroup", label = "Images", groupMembers = { "navLeft", "navRight" }},
          { id = "navLeft", image = hs.image.imageFromName("NSGoLeftTemplate"), allowedAlone = false },
          { id = "navRight", image = hs.image.imageFromName("NSGoRightTemplate"), allowedAlone = false },
          { id = "lightGroup", label = "YeeLight Control", groupMembers = { "lightGreen", "lightAmber", "lightRed", "lightOff" }},
          { id = "lightGreen", image = hs.image.imageFromName("NSStatusAvailable"), allowedAlone = false },
          { id = "lightAmber", image = hs.image.imageFromName("NSStatusIdle"), allowedAlone = false },
          { id = "lightRed", image = hs.image.imageFromName("NSStatusAway"), allowedAlone = false },
          { id = "lightOff", image = hs.image.imageFromName("NSStatusUnknown"), allowedAlone = false },
      }):canCustomize(false)
        :autosaves(false)
        :toolbarStyle("unifiedCompact")
        :setCallback(function(tb, wv, button)
          if button == "ON/OFF" then
            toggleHyperPixel()
            if hyperPixelDesiredState == true then
              newImageName = "NSWinHighSwitch"
            else
              newImageName = "NSWinSwitch"
            end
            cw:attachedToolbar():modifyItem({ id = "ON/OFF", image = hs.image.imageFromName(newImageName) })
          elseif button == "navLeft" then
            sendToHyperPixel("previous")
          elseif button == "navRight" then
            sendToHyperPixel("next")
          elseif button == "lightGreen" then
            setLightGreen()
          elseif button == "lightAmber" then
            setLightAmber()
          elseif button == "lightRed" then
            setLightRed()
          elseif button == "lightOff" then
            setLightOff()
          else
            _debug('WTF? ' .. button)
          end
        end)

  t.attachToolbar(cw, a)
  cw:show()
  hyperPixelControlWindow = cw
end

function sendPingToHyperPixel()
  if hyperPixelSocket ~= nil and hyperPixelSocket:connected() then
    sendToHyperPixel("ping")
  end
end

function hyperPixelConnected()
  _debug("HyperPixel connected successfully!")
  hyperPixelConnectTimer:stop()
  if hyperPixelControlWindow ~= nil then
    hyperPixelControlWindow:show()
  else
    showHyperPixelControlWindow()
  end
  if hyperPixelPingTimer ~= nil then
    hyperPixelPingTimer:stop()
  end
  hyperPixelPingTimer = hs.timer.doEvery(30, sendPingToHyperPixel)
  hyperPixelPingTimer:start()
  hyperPixelDesiredState = true
end

function clusterMonitorConnected()
  _debug("ClusterPi Monitor connected successfully!")
end

function connectToHyperPixel()
  if hyperPixelSocket == nil or not hyperPixelSocket:connected() then
    _debug("Connecting to HyperPixel Pi...")
    hyperPixelConnectTimer:start()
    hyperPixelSocket = hs.socket.new(hyperPixelSocketCallback):setTimeout(30):connect('hyperpixel.local', 4242, hyperPixelConnected)
  end
  if chartMonitorSocket == nil or not chartMonitorSocket:connected() then
    _debug("Connecting to ClusterPi Monitor...")
    chartMonitorSocket = hs.socket.new(chartMonitorSocketCallback):setTimeout(30):connect('clusterpi.local', 4242, clusterMonitorConnected)
  end
end

function disconnectFromHyperPixel()
  if hyperPixelSocket ~= nil then
    _debug("Disconnecting from HyperPixel Pi...")
    if hyperPixelPingTimer ~= nil then
      hyperPixelPingTimer:stop()
      hyperPixelPingTimer = nil
    end
    hyperPixelSocket:disconnect()
    hyperPixelSocket:setCallback(nil)
    hyperPixelSocket = nil
  end
  if chartMonitorSocket ~= nil then
    _debug("Disconnecting from ClusterPi Monitor...")
    chartMonitorSocket:disconnect()
    chartMonitorSocket = nil
  end
  if hyperPixelControlWindow ~= nil then
    hyperPixelControlWindow:hide()
  end
end

function screenLocked()
  _debug("Screen locked")
  isScreenLocked = true
  updateLightStatus()
  turnOffHyperPixel()
  for lightID, brightness in pairs(lights) do
    spoon.Hue:setLightState(lightID, "false", brightness)
  end
end

function screenUnlocked()
  _debug("Screen unlocked")
  isScreenLocked = false
  updateLightStatus()
  if hyperPixelEnabled then
    if hyperPixelSocket == nil or not hyperPixelSocket:connected() then
      connectToHyperPixel()
    else
      turnOnHyperPixel()
    end
    if hyperPixelDesiredState == true then
      turnOnHyperPixel()
    end
  end
  if not spoon.Yeelight:connected() then
    spoon.Yeelight:start()
  end
  for lightID, brightness in pairs(lights) do
    spoon.Hue:setLightState(lightID, "true", brightness)
  end
end

function goingToSleep()
  _debug("Going to sleep, shutting down")
  disconnectFromHyperPixel()
  spoon.Yeelight:stop()
  spoon.Zoom:kill()
end

function citrixStarted()
  _debug("Citrix started")
  isCitrixRunning = true
  updateLightStatus()
end

function citrixStopped()
  _debug("Citrix stopped")
  isCitrixRunning = false
  updateLightStatus()
end

-- Connect to Yeelight bulb
spoon.Yeelight:start('10.0.0.93', 55443)

-- Listen to Citrix events
updateCitrixStatus = function(event)
  _debug("citrixStatus(%s)", event)
  if event == "citrixStarted" then
    citrixStarted()
  elseif event == "citrixStopped" then
    citrixStopped()
  end
end
spoon.CitrixViewer:setStatusCallback(updateCitrixStatus)
spoon.CitrixViewer:start()

-- Listen to Zoom events
updateZoomStatus = function(event)
  _debug("updateZoomStatus(%s)", event)
  if event == "from-running-to-meeting" then
    meetingStart()
  elseif event == "muted" then
    micMuted()
  elseif event == "unmuted" then
    micUnmuted()
  elseif event == "videoStarted" then
    videoOn()
  elseif event == "videoStopped" then
    videoOff()
  elseif (event == "from-running-to-closed") or (event == 'from-meeting-to-running') then
    meetingOff()
  else
    _debug("unhandled event: %s", event)
  end
end
spoon.Zoom:setStatusCallback(updateZoomStatus)
spoon.Zoom:pollStatus(pollingInterval)
spoon.Zoom:start()
inZoomMeeting = spoon.Zoom:inMeeting()

-- check for screen lock/unlock events
local function on_caffeine_event(event)
  local name = "?"
  for key,val in pairs(hs.caffeinate.watcher) do
    if event == val then name = key end
  end
  _debug("caffeinate event %d => %s", event, name)
  if event == hs.caffeinate.watcher.screensDidUnlock
  then
    screenUnlocked()
  elseif event == hs.caffeinate.watcher.screensDidLock
  then
    screenLocked()
  elseif event == hs.caffeinate.watcher.systemWillSleep
  then
    goingToSleep()
  elseif event == hs.caffeinate.watcher.systemWillPowerOff
  then
    goingToSleep()
  end
end
lock_watcher = hs.caffeinate.watcher.new(on_caffeine_event)
lock_watcher:start()

-- set initial LED status
updateLightStatus()

-- Connect to HyperPixel Pi (if running)
if hyperPixelEnabled then
  hyperPixelConnectTimer = hs.timer.delayed.new(10, connectToHyperPixel)
  connectToHyperPixel()
end

-- Detect camera in-use changes
cameraCallback = function(camera, propertyChanged)
  _debug("Camera %s in use? %s", camera:name(), camera:isInUse())
  isCameraInUse = camera:isInUse()
  updateLightStatus()
  if isCameraInUse then
    spoon.Hue:setLightState(ceilingLightID, "true", 50)
  else
    spoon.Hue:setLightState(ceilingLightID, "true", 200)
  end
end

require("hs.camera")
for _, camera in pairs(hs.camera.allCameras()) do
  camera:setPropertyWatcherCallback(cameraCallback)
  camera:startPropertyWatcher()
end

local hueSetupDone = false
hueReady = function()
  if not hueSetupDone then
    _debug("Setting up Hue Lights...")
    ceilingLightID = spoon.Hue:getBulbs("Ceiling Light")
    lights[ceilingLightID] = 200
    lights[spoon.Hue:getBulbs("Corner light")] = 255
    lights[spoon.Hue:getBulbs("Hue Play Left")] = 255
    lights[spoon.Hue:getBulbs("Hue Play Center")] = 255
    lights[spoon.Hue:getBulbs("Hue Play Right")] = 255
    hueSetupDone = true
  end
end
hs.loadSpoon("Hue")
spoon.Hue.ip = "10.0.0.242"
spoon.Hue:setReadyCallback(hueReady)
spoon.Hue:updateURLs()
spoon.Hue:init()

