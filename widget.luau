--!nonstrict
-- Bar widget: the workspaces on this bar's monitor. Hovering one asks the
-- service for a preview; clicking or scrolling switches workspace.

local function dispatch(arg: string)
  noctalia.runAsync({ "hyprctl", "dispatch", "workspace", arg })
end

local function render()
  local output = barWidget.outputName()
  local vertical = barWidget.isVertical()
  local container = if vertical then ui.column else ui.row
  local items = {}

  for _, ws in ipairs(noctalia.state.get("workspaces") or {}) do
    if output == nil or ws.monitor == output then
      local current = ws.visible
      table.insert(items, container({
        key = ws.id,
        align = "center",
        justify = "center",
        paddingH = if vertical then 0 else 8,
        paddingV = if vertical then 6 else 0,
        radius = 5,
        -- Always explicit: Noctalia keeps a row's old fill when the prop is dropped.
        fill = if current then "primary" else "#00000000",
        onHover = function(state)
          noctalia.state.set("hover_ws", if state == "true" then ws.id else "")
        end,
        onClick = function()
          noctalia.state.set("dismiss", noctalia.nowMs())
          dispatch(tostring(ws.num))
        end,
      }, {
        ui.label({
          text = ws.name,
          color = if current then "on_primary" elseif ws.windows == 0 then "on_surface_variant" else nil,
          fontSize = 11, -- the built-in workspaces widget's label size
          maxWidth = 160,
          maxLines = 1,
        }),
      }))
    end
  end

  barWidget.render(container({ gap = 4, align = "stretch" }, items))
end

function onScroll(axis, steps, startsGesture)
  if axis ~= "vertical" or not startsGesture then
    return
  end
  dispatch(if steps > 0 then "m+1" else "m-1")
end

noctalia.state.watch("workspaces", render)

render()
