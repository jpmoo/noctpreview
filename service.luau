--!nonstrict
-- Runs the Hyprland helper, publishes what it reports, and opens/closes the
-- preview panel from the hover state the bar widget publishes.

local layout = require("./lib/layout.luau")

local helperPid: number? = nil
local snaps = {}
local openPanel: string? = nil -- the preview variant showing, if any
local hoverWs = ""
local hoverChanged = 0

local function shq(s: string): string
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function signalHelper(sig: string)
  if helperPid then
    noctalia.runAsync({ "kill", "-" .. sig, tostring(helperPid) })
  end
end

-- The preview variant tall enough for this workspace's app list.
local function panelFor(ws: string): string
  local apps = (noctalia.state.get("clients") or {})[ws] or {}
  return layout.panelId(layout.rows(#apps))
end

-- Panel commands run one at a time, in order: a quick leave-and-return must
-- not let "open" overtake the "close" issued before it.
local queue = {}
local running = false

local function drain()
  if running or #queue == 0 then
    return
  end
  running = true
  noctalia.runAsync(table.remove(queue, 1), function()
    running = false
    drain()
  end)
end

local function panelMsg(verb: string, id: string)
  table.insert(queue, { "noctalia", "msg", verb, id })
  drain()
end

-- Show `id` (or nothing, for nil), swapping variants when the list length changes.
-- Uses the explicit open/close commands rather than togglePanel: they are
-- idempotent, so a missed transition can never leave the wrong panel up.
local function show(id: string?)
  if id == openPanel then
    return
  end
  local was = openPanel
  openPanel = id
  for rows = 1, layout.MAX_ROWS do
    local other = layout.panelId(rows)
    if other ~= id then
      panelMsg("panel-close", other)
    end
  end
  if id then
    panelMsg("panel-open", id)
  end
  -- The helper would photograph the preview itself; hold captures while it shows.
  if (was == nil) ~= (id == nil) then
    signalHelper(if id then "USR1" else "USR2")
  end
end

local function panelOpen(): boolean
  return openPanel ~= nil
end

noctalia.state.set("hover_ws", "")
noctalia.state.set("peek_ws", "")

noctalia.state.watch("hover_ws", function(value)
  value = value or ""
  if value ~= hoverWs then
    hoverWs = value
    hoverChanged = noctalia.nowMs()
    if value ~= "" and panelOpen() then
      noctalia.state.set("peek_ws", value) -- moving along the bar swaps the preview at once
      show(panelFor(value))
    end
  end
end)

-- A click switches workspace: close straight away rather than after the leave delay.
noctalia.state.watch("dismiss", function()
  hoverWs = ""
  show(nil)
end)

local function onLine(line: string)
  local msg = noctalia.json.decode(line)
  if type(msg) ~= "table" then
    return
  end
  if msg.type == "pid" then
    helperPid = msg.pid
  elseif msg.type == "state" then
    noctalia.state.set("workspaces", msg.workspaces or {})
    noctalia.state.set("clients", msg.clients or {})
    local peek = noctalia.state.get("peek_ws") or ""
    if panelOpen() and peek ~= "" then
      show(panelFor(peek)) -- a window opened or closed under the preview
    end
  elseif msg.type == "snap" then
    local copy = table.clone(snaps)
    if msg.path then
      copy[msg.ws] = { path = msg.path, t = msg.t }
    else
      copy[msg.ws] = nil
    end
    snaps = copy
    noctalia.state.set("snaps", copy)
  elseif msg.type == "error" then
    noctalia.log("workspace-peek: " .. tostring(msg.message))
  end
end

local dataDir = noctalia.pluginDataDir()
local script = `{noctalia.pluginDir()}/scripts/peek.py`
local refresh = noctalia.getConfig("refresh_seconds") or 30

noctalia.runStream(
  `exec python3 -u {shq(script)} {shq(dataDir .. "/snaps")} {refresh}`,
  onLine
)

noctalia.setUpdateInterval(50)

function update()
  local elapsed = noctalia.nowMs() - hoverChanged
  if hoverWs ~= "" and not panelOpen() then
    if elapsed >= (noctalia.getConfig("hover_delay_ms") or 250) then
      noctalia.state.set("peek_ws", hoverWs)
      show(panelFor(hoverWs))
    end
  elseif hoverWs == "" and panelOpen() and elapsed >= 150 then
    show(nil)
  end
end

function onExit()
  -- Callbacks die with this runtime, so close everything in one detached shell.
  local cmds = {}
  for rows = 1, layout.MAX_ROWS do
    table.insert(cmds, `noctalia msg panel-close {layout.panelId(rows)}`)
  end
  noctalia.runAsync(table.concat(cmds, "; "))
  signalHelper("TERM")
end

