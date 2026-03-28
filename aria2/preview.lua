local M = {}

local SECTION_META = {
  incomplete = {
    title = 'Incomplete',
    description = 'Show active, waiting, paused, and failed tasks.',
    color = 'yellow',
  },
  completed = {
    title = 'Completed',
    description = 'Show recently completed tasks.',
    color = 'cyan',
  },
}

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end
local function text(lines) return lc.style.text(lines) end

local function trim(s)
  if not s then return '' end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function primary_file(task)
  local files = task and task.files or {}
  if not files or #files == 0 then return nil end
  for _, file in ipairs(files) do
    local path = trim(file.path)
    if path ~= '' then return file end
  end
  return files[1]
end

local function task_name(task)
  local file = primary_file(task)
  if file then
    local path = trim(file.path)
    if path ~= '' then return path:match '[^/]+$' or path end
    for _, uri in ipairs(file.uris or {}) do
      local uri_value = trim(uri.uri)
      if uri_value ~= '' then return uri_value end
    end
  end
  return 'gid:' .. tostring(task and task.gid or '?')
end

local function task_path(task)
  local file = primary_file(task)
  if not file then return nil end
  local path = trim(file.path)
  if path ~= '' then return path end
  return nil
end

local function task_status_text(status)
  local mapping = {
    active = 'Active',
    waiting = 'Waiting',
    paused = 'Paused',
    error = 'Error',
    complete = 'Completed',
    removed = 'Removed',
  }
  return mapping[status] or tostring(status or '-')
end

local function task_status_color(status)
  local mapping = {
    active = 'green',
    waiting = 'yellow',
    paused = 'magenta',
    error = 'red',
    complete = 'cyan',
    removed = 'darkgray',
  }
  return mapping[status] or 'white'
end

local function format_bytes(value)
  local n = tonumber(value) or 0
  if n < 1024 then return string.format('%d B', n) end
  local units = { 'KiB', 'MiB', 'GiB', 'TiB' }
  local size = n / 1024
  for i, unit in ipairs(units) do
    if size < 1024 or i == #units then return string.format('%.1f %s', size, unit) end
    size = size / 1024
  end
  return string.format('%.1f TiB', size)
end

local function format_speed(value)
  local n = tonumber(value) or 0
  if n <= 0 then return '0 B/s' end
  return format_bytes(n) .. '/s'
end

local function format_percent(done, total)
  local d = tonumber(done) or 0
  local t = tonumber(total) or 0
  if t <= 0 then return '0%' end
  return string.format('%.1f%%', (d / t) * 100)
end

local function format_eta(done, total, speed)
  local d = tonumber(done) or 0
  local t = tonumber(total) or 0
  local s = tonumber(speed) or 0
  if t <= 0 or s <= 0 or d >= t then return '-' end
  local left = math.floor((t - d) / s)
  local h = math.floor(left / 3600)
  local m = math.floor((left % 3600) / 60)
  local sec = left % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, sec) end
  return string.format('%d:%02d', m, sec)
end

function M.section_preview(entry)
  local meta = SECTION_META[entry.section]
  return text {
    line { span(meta.title, meta.color) },
    line { span(meta.description, 'white') },
  }
end

local function field_line(label, value, label_color, value_color)
  return line {
    span(label, label_color or 'blue'),
    span(value == nil or value == '' and '-' or tostring(value), value_color or 'white'),
  }
end

function M.task_preview(entry)
  local task = entry.task or {}
  local done = tonumber(task.completedLength) or 0
  local total = tonumber(task.totalLength) or 0
  local speed = tonumber(task.downloadSpeed) or 0
  local upload = tonumber(task.uploadSpeed) or 0
  local file_path = task_path(task) or '-'
  local fields = {
    field_line('Status: ', task_status_text(task.status), 'blue', task_status_color(task.status)),
    field_line('GID: ', task.gid or '-', 'blue', 'white'),
    field_line('Progress: ', format_percent(done, total), 'blue', 'cyan'),
    field_line('Completed: ', format_bytes(done), 'blue', 'white'),
    field_line('Total: ', format_bytes(total), 'blue', 'white'),
    field_line('Down: ', format_speed(speed), 'blue', 'yellow'),
    field_line('Up: ', format_speed(upload), 'blue', 'yellow'),
    field_line('Connections: ', task.connections or '-', 'blue', 'white'),
    field_line('ETA: ', format_eta(done, total, speed), 'blue', 'white'),
    field_line('File: ', file_path, 'blue', 'white'),
  }

  if task.errorCode and tostring(task.errorCode) ~= '' then
    table.insert(fields, field_line('Error code', task.errorCode, 'blue', 'red'))
  end
  if task.errorMessage and trim(task.errorMessage) ~= '' then
    table.insert(fields, field_line('Error message', task.errorMessage, 'blue', 'red'))
  end

  lc.style.align_columns(fields)

  local lines = {
    line { span(task_name(task), 'white') },
    line { '' },
  }
  for _, item in ipairs(fields) do
    table.insert(lines, item)
  end

  return text(lines)
end

function M.info_preview(entry)
  return text {
    line { span(entry.preview_message or 'aria2', 'yellow') },
  }
end

return M
