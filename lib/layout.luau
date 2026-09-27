--!nonstrict
-- Shared by the service (which picks a panel) and the preview (which fills it).
-- Plugin panels have a fixed height, so plugin.toml declares one panel per
-- number of list rows; these numbers must agree with the heights there.

local M = {}

M.MAX_APPS = 4 -- beyond this the last row reads "+N more"
M.MAX_ROWS = M.MAX_APPS + 1
M.THUMB_W = 328 -- a 380-wide panel leaves 328 once its inset and ours are taken
M.THUMB_H = 205 -- 16:10; other shapes letterbox inside it
M.HEADER_H = 22
M.ROW_H = 22
M.ROW_GAP = 5

-- How many rows the app list needs for a workspace with `count` windows.
function M.rows(count: number): number
  if count == 0 then
    return 1 -- "No windows open"
  elseif count > M.MAX_APPS then
    return M.MAX_ROWS
  end
  return count
end

function M.panelId(rows: number): string
  return `jpmoo/workspace-peek:preview{rows}`
end

return M
