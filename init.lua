-- This script will control a warning LED to let family members know
-- to now come in during a Zoom meeting

-- Using Zoom spoon from: https://github.com/brunon/Zoom.spoon
-- Forked from: https://github.com/jpf/Zoom.spoon
hs.loadSpoon("Zoom")

-- CitrixViewer spoon from: https://github.com/brunon/CitrixViewer.spoon
hs.loadSpoon("CitrixViewer")

local inZoomMeeting = false
local isMuted = true -- zoom starts on Mute ...
local isVideoOn = false -- ... with video off
local debug = false
local isScreenLocked = false
local isCitrixRunning = false
local pollingInterval = 2 -- seconds

function updateLightStatus()
  if isScreenLocked or not isCitrixRunning then
    -- screen is locked, turn off warning LED
    if debug then
      hs.printf("LED OFF")
    end
    hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "off"]])
  elseif inZoomMeeting then
    if isVideoOn or not isMuted then
      if debug then
        hs.printf("LED RED")
      end
      hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "dnd"]])
    else
      if debug then
        hs.printf("LED AMBER")
      end
      hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "warning"]])
    end
  else
    if debug then
      hs.printf("LED GREEN")
    end
    hs.execute([["/usr/bin/python3" "/Users/brunonavert/.hammerspoon/yeelight-office.py" "--mode" "work"]])
  end
end

function micMuted()
  if debug then
    hs.printf("Mute ON")
  end
  isMuted = true
  updateLightStatus()
end

function micUnmuted()
  if debug then
    hs.printf("Mute OFF")
  end
  isMuted = false
  updateLightStatus()
end

function meetingOff()
  if debug then
    hs.printf("Meeting closed")
  end
  inZoomMeeting = false
  isMuted = true
  isVideoOn = false
  updateLightStatus()
end

function meetingStart()
  if debug then
    hs.printf("Meeting start")
  end
  inZoomMeeting = true
  updateLightStatus()
end

function videoOn()
  if debug then
    hs.printf("Video turned ON")
  end
  isVideoOn = true
  updateLightStatus()
end

function videoOff()
  if debug then
    hs.printf("Video turned OFF")
  end
  isVideoOn = false
  updateLightStatus()
end

function screenLocked()
  if debug then
    hs.printf("Screen locked")
  end
  isScreenLocked = true
  updateLightStatus()
end

function screenUnlocked()
  if debug then
    hs.printf("Screen unlocked")
  end
  isScreenLocked = false
  updateLightStatus()
end

function citrixStarted()
  if debug then
    hs.printf("Citrix started")
  end
  isCitrixRunning = true
  updateLightStatus()
end

function citrixStopped()
  if debug then
    hs.printf("Citrix stopped")
  end
  isCitrixRunning = false
  updateLightStatus()
end

-- Listen to Citrix events
updateCitrixStatus = function(event)
  if debug then
    hs.printf("citrixStatus(%s)", event)
  end
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
  if debug then
    hs.printf("updateZoomStatus(%s)", event)
  end
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

-- check for screen lock/unlock events
local function on_caffeine_event(event)
  local name = "?"
  for key,val in pairs(hs.caffeinate.watcher) do
    if event == val then name = key end
  end
  if debug then
    hs.printf("caffeinate event %d => %s", event, name)
  end
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
