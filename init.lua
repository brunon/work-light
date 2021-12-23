-- This script will control a warning LED to let family members know
-- to now come in during a Zoom meeting

-- Using Zoom spoon from: https://github.com/brunon/Zoom.spoon
-- Forked from: https://github.com/jpf/Zoom.spoon
hs.loadSpoon("Zoom")

-- CitrixViewer spoon from: https://github.com/brunon/CitrixViewer.spoon
hs.loadSpoon("CitrixViewer")

local inZoomMeeting = false
local isMuted = false
local isVideoOn = false
local debug = true
local isScreenLocked = false
local isCitrixRunning = false
local pollingInterval = 2 -- seconds
local ledMode = "off"
local hyperPixelSocket = nil
local hyperPixelControlWindow = nil
local hyperPixelDesiredState = false

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

function updateLightStatus()
  if isScreenLocked or not isCitrixRunning or isWeekend() then
    -- screen is locked, turn off warning LED
    _debug("LED %s => off", ledMode)
    if ledMode ~= "off" then
      hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "off"]])
      ledMode = "off"
    end
  elseif inZoomMeeting then
    _debug("LED %s => dnd", ledMode)
    if ledMode ~= "dnd" then
      hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "dnd"]])
      ledMode = "dnd"
    end
  else
    _debug("LED %s => work", ledMode)
    if ledMode ~= "work" then
      hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "work"]])
      ledMode = "work"
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
  inZoomMeeting = true
  updateLightStatus()
end

function videoOn()
  _debug("Video turned ON")
  isVideoOn = true
  updateLightStatus()
end

function videoOff()
  _debug("Video turned OFF")
  isVideoOn = false
  updateLightStatus()
end

function hyperPixelSocketCallback(data, tag)
  _debug("Got data from socket: " .. data)
end


function sendToHyperPixel(command, ...)
  if hyperPixelSocket ~= nil and hyperPixelSocket.connected then
    if hyperPixelSocket.connected then
      message = string.format(command, ...)
      hyperPixelSocket:send(message)
      _debug("Sending to HyperPixel: %s", message)
    else
      _debug("HyperPixel Connection Lost!")
      disconnectFromHyperPixel()
    end
  end
end

function turnOnHyperPixel()
  sendToHyperPixel("on")
end

function turnOffHyperPixel()
  sendToHyperPixel("off")
end

function showHyperPixelControlWindow()
  cw = hs.webview.newBrowser(hs.geometry.rect(960, 1150, 450, 250))
  cw:windowStyle({"titled", "nonactivating"}):windowTitle("HyperPixel Controls"):url("http://hyperpixel.local/")

  t = require("hs.webview.toolbar")
  a = t.new("HyperPixel Controls", {
          { id = "ON", selectable = true, image = hs.image.imageFromName("NSStatusAvailable") },
          { id = "OFF", selectable = true, image = hs.image.imageFromName("NSStatusUnavailable") },
          { id = "navGroup", label = "Navigation", groupMembers = { "navLeft", "navRight" }},
          { id = "navLeft", image = hs.image.imageFromName("NSGoLeftTemplate"), allowedAlone = false },
          { id = "navRight", image = hs.image.imageFromName("NSGoRightTemplate"), allowedAlone = false },
          { id = "Close", selectable = true, image = hs.image.imageFromName("NSNavEjectButton.normal") },
      }):canCustomize(false)
        :autosaves(true)
        :selectedItem("OFF")
        :setCallback(function(tb, wv, button)
          if button == "ON" then
            _debug("ON pressed")
            hyperPixelDesiredState = true
            turnOnHyperPixel()
          elseif button == "OFF" then
            _debug("OFF pressed")
            hyperPixelDesiredState = false
            turnOffHyperPixel()
          elseif button == "Close" then
            disconnectFromHyperPixel()
          elseif button == "navLeft" then
            sendToHyperPixel("previous")
          elseif button == "navRight" then
            sendToHyperPixel("next")
          else
            _debug('WTF? ' .. button)
          end
        end)

  t.attachToolbar(cw, a)
  cw:show()
  hyperPixelControlWindow = cw
end

function connectToHyperPixel()
  if hyperPixelSocket == nil then
    _debug("Connecting to HyperPixel Pi...")
    hyperPixelSocket = hs.socket.new():connect('hyperpixel.local', 4242)
    if hyperPixelSocket == nil then
      _debug("Error connecting to HyperPixel Pi!")
    elseif hyperPixelControlWindow ~= nil then
      hyperPixelControlWindow:show()
    else
      showHyperPixelControlWindow()
    end
  end
end

function disconnectFromHyperPixel()
  if hyperPixelSocket ~= nil then
    turnOffHyperPixel()
    _debug("Disconnecting from HyperPixel Pi...")
    hyperPixelSocket:disconnect()
    hyperPixelSocket:setCallback(nil)
    hyperPixelSocket = nil
  end
  if hyperPixelControlWindow ~= nil then
    hyperPixelControlWindow:hide()
  end
end

function screenLocked()
  _debug("Screen locked")
  isScreenLocked = true
  updateLightStatus()
  disconnectFromHyperPixel()
end

function screenUnlocked()
  _debug("Screen unlocked")
  isScreenLocked = false
  updateLightStatus()
  connectToHyperPixel()
  if hyperPixelDesiredState == true then
    turnOnHyperPixel()
  end
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
  elseif event == "from-meeting-to-running" then
    meetingOff()
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
  end
end
lock_watcher = hs.caffeinate.watcher.new(on_caffeine_event)
lock_watcher:start()

-- set initial LED status
updateLightStatus()

-- Connect to HyperPixel Pi (if running)
connectToHyperPixel()
