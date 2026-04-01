local M = {}

local api = require 'aria2.api'
local config = require 'aria2.config'
local metas = require 'aria2.metas'

local state = {
  runtime_setup = false,
  enter_hook_registered = false,
  poll_generation = 0,
  poll_pending = false,
}

local SECTION_META = {
  incomplete = {
    title = 'Incomplete',
    description = 'Show active, waiting, paused, and failed tasks.',
    empty = 'No incomplete tasks',
    color = 'yellow',
  },
  completed = {
    title = 'Completed',
    description = 'Show recently completed tasks.',
    empty = 'No completed tasks',
    color = 'cyan',
  },
}

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end
local show_error
local maybe_poll_incomplete
local refresh_incomplete_entries

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
  end
  return 'gid:' .. tostring(task and task.gid or '?')
end

local function current_path()
  return lc.api.get_current_path() or {}
end

local function path_is_aria2_child(path)
  path = path or current_path()
  return path[1] == 'aria2' and #path >= 2
end

local function path_is_incomplete(path)
  path = path or current_path()
  return path[1] == 'aria2' and path[2] == 'incomplete'
end

local function invalidate_current_page_cache(path)
  path = path or current_path()
  if path_is_aria2_child(path) then lc.api.clear_page_cache(path) end
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

local function section_entries()
  local entries = {}
  for _, key in ipairs { 'incomplete', 'completed' } do
    local meta = SECTION_META[key]
    table.insert(entries, {
      key = key,
      kind = 'section',
      section = key,
      display = line {
        span(meta.title, meta.color),
        span('  ·  ', 'darkgray'),
        span(meta.description, 'blue'),
      },
    })
  end
  return entries
end

local function task_entry(task)
  local done = tonumber(task.completedLength) or 0
  local total = tonumber(task.totalLength) or 0
  local speed = tonumber(task.downloadSpeed) or 0
  local display = {
    span(task_status_text(task.status), task_status_color(task.status)),
    span('  ', 'darkgray'),
    span(task_name(task), 'white'),
    span('  ', 'darkgray'),
    span(format_percent(done, total), 'cyan'),
  }
  if task.status == 'active' then
    table.insert(display, span('  ', 'darkgray'))
    table.insert(display, span(format_speed(speed), 'yellow'))
  end
  return {
    key = tostring(task.gid),
    kind = 'task',
    task = task,
    display = line(display),
  }
end

local function status_order(status)
  local order = {
    active = 1,
    waiting = 2,
    paused = 3,
    error = 4,
    removed = 5,
    complete = 6,
  }
  return order[status] or 99
end

local function task_sorter(a, b)
  local sa = status_order(a and a.status)
  local sb = status_order(b and b.status)
  if sa ~= sb then return sa < sb end

  local ga = tostring(a and a.gid or '')
  local gb = tostring(b and b.gid or '')
  return ga < gb
end

local function list_incomplete(cb)
  api.list_active(function(active_tasks, active_err)
    if active_err then
      cb(nil, active_err)
      return
    end

    api.list_waiting(function(waiting_tasks, waiting_err)
      if waiting_err then
        cb(nil, waiting_err)
        return
      end

      api.list_stopped(function(stopped_tasks, stopped_err)
        if stopped_err then
          cb(nil, stopped_err)
          return
        end

        local tasks = {}
        for _, task in ipairs(active_tasks or {}) do
          table.insert(tasks, task)
        end
        for _, task in ipairs(waiting_tasks or {}) do
          table.insert(tasks, task)
        end
        for _, task in ipairs(stopped_tasks or {}) do
          if task.status == 'error' then table.insert(tasks, task) end
        end

        table.sort(tasks, task_sorter)
        cb(tasks)
      end)
    end)
  end)
end

local function incomplete_entries(tasks)
  local entries = {}
  for _, task in ipairs(tasks or {}) do
    table.insert(entries, task_entry(task))
  end

  if #entries == 0 then
    table.insert(entries, {
      key = 'empty',
      kind = 'info',
      info_keymap = 'reload_add',
      preview_message = 'No tasks',
      display = line { span(SECTION_META.incomplete.empty, 'darkgray') },
    })
  end

  return entries
end

local function completed_entries(tasks)
  local entries = {}
  for _, task in ipairs(tasks or {}) do
    table.insert(entries, task_entry(task))
  end

  if #entries == 0 then
    table.insert(entries, {
      key = 'empty',
      kind = 'info',
      info_keymap = 'reload_add',
      preview_message = 'No tasks',
      display = line { span(SECTION_META.completed.empty, 'darkgray') },
    })
  end

  return entries
end

local function tasks_from_entries(entries)
  local tasks = {}
  for _, entry in ipairs(entries or {}) do
    if entry.kind == 'task' and entry.task then table.insert(tasks, entry.task) end
  end
  return tasks
end

refresh_incomplete_entries = function()
  local path = current_path()
  if not path_is_incomplete(path) then
    state.poll_generation = state.poll_generation + 1
    state.poll_pending = false
    return
  end

  list_incomplete(function(tasks, err)
    if err then
      show_error(err)
      return
    end

    local next_entries = metas.attach_all(incomplete_entries(tasks))
    if lc.deep_equal(path, current_path()) then lc.api.page_set_entries(next_entries) end
    maybe_poll_incomplete(tasks)
  end)
end

local function schedule_incomplete_refresh()
  if state.poll_pending then return end
  state.poll_pending = true
  local generation = state.poll_generation
  lc.defer_fn(function()
    state.poll_pending = false
    if generation ~= state.poll_generation then return end
    if not path_is_incomplete() then return end
    refresh_incomplete_entries()
  end, 1000)
end

maybe_poll_incomplete = function(tasks)
  if not path_is_incomplete() then
    state.poll_generation = state.poll_generation + 1
    state.poll_pending = false
    return
  end

  local has_active = false
  for _, task in ipairs(tasks or {}) do
    if task.status == 'active' then
      has_active = true
      break
    end
  end

  if not has_active then
    state.poll_generation = state.poll_generation + 1
    state.poll_pending = false
    return
  end

  schedule_incomplete_refresh()
end

local function register_enter_hook()
  if state.enter_hook_registered then return end
  state.enter_hook_registered = true

  lc.hook.post_page_enter(function(ctx)
    local path = (ctx and ctx.path) or {}
    if path_is_aria2_child(path) then
      invalidate_current_page_cache(path)
      if not path_is_incomplete(path) then
        state.poll_generation = state.poll_generation + 1
        state.poll_pending = false
      end
    else
      state.poll_generation = state.poll_generation + 1
      state.poll_pending = false
    end
  end)
end

local function setup_runtime()
  if state.runtime_setup then return end
  state.runtime_setup = true
  register_enter_hook()
end

local function list_section(section, cb)
  if section == 'incomplete' then
    list_incomplete(function(tasks, err)
      if err then
        cb(nil, err)
        return
      end

      cb(incomplete_entries(tasks))
    end)
    return
  end

  local loader = api.list_completed

  loader(function(tasks, err)
    if err then
      cb(nil, err)
      return
    end

    cb(completed_entries(tasks))
  end)
end

show_error = function(err)
  lc.notify(line {
    span('aria2: ', 'red'),
    span(err or 'unknown error', 'red'),
  })
end

function M.setup(opt) config.setup(opt) end

function M.list(path, cb)
  setup_runtime()
  local ok, err = api.ensure_configured()
  if not ok then
    cb(metas.attach_all {
      {
        key = 'not-configured',
        kind = 'info',
        info_keymap = 'reload',
        preview_message = tostring(err),
        display = line { span('Configure aria2 via setup() or ARIA2_RPC_URL', 'yellow') },
      },
    })
    return
  end

  if path and path[1] == 'aria2' then path = { table.unpack(path, 2) } end

  if not path or #path == 0 then
    state.poll_generation = state.poll_generation + 1
    state.poll_pending = false
    cb(metas.attach_all(section_entries()))
    return
  end

  if SECTION_META[path[1]] then
    list_section(path[1], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb(metas.attach_all {
          {
            key = 'error',
            kind = 'info',
            info_keymap = 'reload_add',
            preview_message = tostring(list_err or 'aria2 request failed'),
            display = line { span('aria2 request failed', 'red') },
          },
        })
        return
      end
      if path[1] == 'incomplete' then
        maybe_poll_incomplete(tasks_from_entries(entries))
      else
        state.poll_generation = state.poll_generation + 1
        state.poll_pending = false
      end
      cb(metas.attach_all(entries))
    end)
    return
  end

  state.poll_generation = state.poll_generation + 1
  state.poll_pending = false
  cb(metas.attach_all {})
end

function M.preview(entry, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb(err)
    return
  end

  if not entry then
    cb ''
    return
  end

  if type(entry.preview) == 'function' then
    entry:preview(cb)
    return
  end

  cb 'aria2'
end

return M
