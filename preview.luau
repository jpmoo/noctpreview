--!nonstrict
-- The hover preview: the workspace's last snapshot and the apps open on it.

local layout = require("./lib/layout.luau")

local function findWorkspace(id: string)
  for _, ws in ipairs(noctalia.state.get("workspaces") or {}) do
    if ws.id == id then
      return ws
    end
  end
  return nil
end

local function age(t: number): string
  local s = math.max(0, os.time() - t)
  if s < 10 then
    return noctalia.tr("just_now")
  elseif s < 60 then
    return noctalia.tr("ago_seconds", { n = s })
  elseif s < 3600 then
    return noctalia.tr("ago_minutes", { n = s // 60 })
  end
  return noctalia.tr("ago_hours", { n = s // 3600 })
end

-- "com.anthropic.Claude" -> "Claude", "org.gnome.Nautilus" -> "Nautilus"
local function appName(class: string): string
  local last = class:match("([^%.]+)$") or class
  if last == "" then
    return "?"
  end
  return last:sub(1, 1):upper() .. last:sub(2)
end

local function render()
  local id = noctalia.state.get("peek_ws") or ""
  local ws = findWorkspace(id)
  local snap = (noctalia.state.get("snaps") or {})[id]
  local apps = (noctalia.state.get("clients") or {})[id] or {}

  local header = ui.row({ height = layout.HEADER_H, align = "center", gap = 8 }, {
    ui.label({ text = if ws then ws.name else id, fontWeight = "bold", flexGrow = 1, maxLines = 1 }),
    ui.label({ text = if snap then age(snap.t) else "", color = "on_surface_variant", fontSize = 11 }),
  })

  local thumb
  if snap then
    thumb = ui.image({ key = "thumb", path = snap.path, width = layout.THUMB_W, height = layout.THUMB_H, radius = 6, fit = "contain",
      border = "outline/0.4", borderWidth = 1 })
  else
    thumb = ui.column({ key = "empty", height = layout.THUMB_H, radius = 6, fill = "surface_container_high",
      border = "outline/0.4", borderWidth = 1, align = "center", justify = "center", gap = 6 }, {
      ui.glyph({ name = "photo-off", size = 22, color = "on_surface_variant" }),
      ui.label({ text = noctalia.tr("no_snapshot"), color = "on_surface_variant" }),
    })
  end

  local rows = {}
  if #apps == 0 then
    table.insert(rows, ui.row({ height = layout.ROW_H, align = "center" }, {
      ui.label({ text = noctalia.tr("no_apps"), color = "on_surface_variant" }),
    }))
  end
  for i, app in ipairs(apps) do
    if i > layout.MAX_APPS then
      table.insert(rows, ui.row({ key = "more", height = layout.ROW_H, align = "center" }, {
        ui.label({ text = noctalia.tr("more", { n = #apps - layout.MAX_APPS }), color = "on_surface_variant", fontSize = 11 }),
      }))
      break
    end
    local name = appName(app.class)
    -- Many windows are titled with just the app's name; don't say it twice.
    local title = if app.title:lower() == name:lower() then "" else app.title
    table.insert(rows, ui.row({ key = `app{i}`, height = layout.ROW_H, align = "center", gap = 8 }, {
      ui.glyph({ name = "app-window", size = 14, color = "primary" }),
      ui.label({ text = name, fontWeight = "bold", maxLines = 1 }),
      ui.label({ text = title, color = "on_surface_variant", maxLines = 1, flexGrow = 1, fontSize = 11 }),
    }))
  end

  panel.render(ui.column({ padding = 12, gap = 10 }, {
    header,
    thumb,
    ui.column({ gap = layout.ROW_GAP }, rows),
  }))
end

noctalia.state.watch("peek_ws", render)
noctalia.state.watch("snaps", render)
noctalia.state.watch("clients", render)

function onOpen()
  render()
end

render()
