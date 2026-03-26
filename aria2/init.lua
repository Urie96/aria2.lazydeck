local M = {}
local config = require 'aria2.config'
local api = require 'aria2.api'

local SECTION_META = {
  active = {
    title = '下载中',
    description = '显示 aria2 当前正在下载的任务。',
    empty = '当前没有下载中的任务',
    color = 'green',
  },
  waiting = {
    title = '等待中',
    description = '显示排队等待下载的任务。',
    empty = '当前没有等待中的任务',
    color = 'yellow',
  },
  completed = {
    title = '已完成',
    description = '显示最近已完成的下载任务。',
    empty = '当前没有已完成的任务',
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

local function show_error(err)
  lc.notify(line {
    span('aria2: ', 'red'),
    span(err or 'unknown error', 'red'),
  })
end

local function show_info(msg)
  lc.notify(line {
    span('aria2: ', 'cyan'),
    span(msg or '', 'white'),
  })
end

local function refresh_after_action(msg)
  api.invalidate_cache()
  if msg and msg ~= '' then show_info(msg) end
  lc.cmd 'reload'
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
    active = '下载中',
    waiting = '等待中',
    paused = '暂停',
    error = '失败',
    complete = '已完成',
    removed = '已移除',
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

local function can_open(task)
  local path = task_path(task)
  return task and task.status == 'complete' and path and path ~= ''
end

local function can_pause(task)
  return task and (task.status == 'active' or task.status == 'waiting')
end

local function can_resume(task)
  return task and (task.status == 'paused' or task.status == 'error' or task.status == 'waiting')
end

local function can_remove(task)
  return task and task.gid and task.gid ~= '' and task.status ~= 'removed'
end

local function section_entries()
  local entries = {}
  for _, key in ipairs { 'active', 'waiting', 'completed' } do
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
  return {
    key = tostring(task.gid),
    kind = 'task',
    task = task,
    display = line {
      span(task_status_text(task.status), task_status_color(task.status)),
      span('  ', 'darkgray'),
      span(task_name(task), 'white'),
      span('  ', 'darkgray'),
      span(format_percent(done, total), 'cyan'),
      span('  ', 'darkgray'),
      span(format_speed(speed), 'yellow'),
    },
  }
end

local function list_section(section, cb)
  local loader = section == 'active' and api.list_active
    or section == 'waiting' and api.list_waiting
    or api.list_completed

  loader(function(tasks, err)
    if err then
      cb(nil, err)
      return
    end

    local entries = {}
    for _, task in ipairs(tasks or {}) do
      table.insert(entries, task_entry(task))
    end

    if #entries == 0 then
      table.insert(entries, {
        key = 'empty',
        kind = 'info',
        display = line { span(SECTION_META[section].empty, 'darkgray') },
      })
    end
    cb(entries)
  end)
end

local function section_preview(section)
  local meta = SECTION_META[section]
  return text {
    line { span(meta.title, meta.color) },
    line { span(meta.description, 'white') },
    line { span('', 'white') },
    line { span('Enter 进入列表', 'blue') },
    line { span('n 新增下载', 'blue') },
    line { span('R 清缓存并刷新', 'blue') },
  }
end

local function task_preview(entry)
  local task = entry.task or {}
  local done = tonumber(task.completedLength) or 0
  local total = tonumber(task.totalLength) or 0
  local speed = tonumber(task.downloadSpeed) or 0
  local upload = tonumber(task.uploadSpeed) or 0
  local file_path = task_path(task) or '-'
  local lines = {
    line { span(task_name(task), 'white') },
    line { span('状态: ', 'blue'), span(task_status_text(task.status), task_status_color(task.status)) },
    line { span('GID: ', 'blue'), span(task.gid or '-', 'white') },
    line { span('进度: ', 'blue'), span(format_percent(done, total), 'cyan') },
    line { span('已完成: ', 'blue'), span(format_bytes(done), 'white') },
    line { span('总大小: ', 'blue'), span(format_bytes(total), 'white') },
    line { span('下载速度: ', 'blue'), span(format_speed(speed), 'yellow') },
    line { span('上传速度: ', 'blue'), span(format_speed(upload), 'yellow') },
    line { span('连接数: ', 'blue'), span(task.connections or '-', 'white') },
    line { span('ETA: ', 'blue'), span(format_eta(done, total, speed), 'white') },
    line { span('目录: ', 'blue'), span(task.dir or '-', 'white') },
    line { span('文件: ', 'blue'), span(file_path, 'white') },
  }

  if task.errorCode and tostring(task.errorCode) ~= '' then
    table.insert(lines, line { span('错误码: ', 'blue'), span(task.errorCode, 'red') })
  end
  if task.errorMessage and trim(task.errorMessage) ~= '' then
    table.insert(lines, line { span('错误信息: ', 'blue'), span(task.errorMessage, 'red') })
  end

  table.insert(lines, line { span('', 'white') })
  if can_open(task) then table.insert(lines, line { span('o 打开文件', 'blue') }) end
  if can_pause(task) then table.insert(lines, line { span('p 暂停任务', 'blue') }) end
  if can_resume(task) then table.insert(lines, line { span('r 恢复任务', 'blue') }) end
  if can_remove(task) then table.insert(lines, line { span('dd 删除任务', 'blue') }) end
  table.insert(lines, line { span('Enter / a 打开操作菜单', 'blue') })

  return text(lines)
end

local function info_preview(message)
  return text {
    line { span(message, 'yellow') },
  }
end

local function hovered_task()
  local hovered = lc.api.page_get_hovered()
  if hovered and hovered.kind == 'task' then return hovered.task end
  return nil
end

local function open_task_file(task)
  local path = task_path(task)
  if not path or path == '' then
    show_error 'no file path for selected task'
    return false
  end
  local stat = lc.fs.stat(path)
  if not stat.exists then
    show_error('file does not exist: ' .. path)
    return false
  end
  lc.system.open(path)
  return true
end

local function open_hovered_file()
  local task = hovered_task()
  if not task then return false end
  if not can_open(task) then
    show_error 'selected task has no downloadable file to open'
    return true
  end
  open_task_file(task)
  return true
end

local function pause_hovered_task()
  local task = hovered_task()
  if not task then return false end
  if not can_pause(task) then return false end

  api.pause(task.gid, function(_, err)
    if err then
      show_error(err)
      return
    end
    refresh_after_action('task paused')
  end)
  return true
end

local function resume_hovered_task()
  local task = hovered_task()
  if not task then return false end
  if not can_resume(task) then return false end

  api.resume(task.gid, function(_, err)
    if err then
      show_error(err)
      return
    end
    refresh_after_action('task resumed')
  end)
  return true
end

local function remove_hovered_task()
  local task = hovered_task()
  if not task or not can_remove(task) then return false end

  lc.confirm {
    title = 'Remove aria2 Task',
    prompt = 'Remove task "' .. task_name(task) .. '"?',
    on_confirm = function()
      api.remove(task.gid, task.status, function(_, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action('task removed')
      end)
    end,
  }
  return true
end

local function add_download_from_input()
  lc.input {
    prompt = 'Add download URL',
    placeholder = 'https://example.com/file.iso or magnet:?...',
    on_submit = function(input)
      local uri = trim(input)
      if uri == '' then return end
      api.add_uri(uri, function(gid, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action('download added: ' .. tostring(gid or uri))
      end)
    end,
  }
end

local function task_actions(task)
  local options = {}

  if can_open(task) then
    table.insert(options, {
      value = 'open',
      display = line { span('打开文件', 'cyan') },
    })
  end
  if can_pause(task) then
    table.insert(options, {
      value = 'pause',
      display = line { span('暂停任务', 'yellow') },
    })
  end
  if can_resume(task) then
    table.insert(options, {
      value = 'resume',
      display = line { span('恢复任务', 'green') },
    })
  end
  if can_remove(task) then
    table.insert(options, {
      value = 'remove',
      display = line { span('删除任务', 'red') },
    })
  end

  if #options == 0 then
    show_info 'no available actions for selected task'
    return true
  end

  lc.select({
    prompt = 'Select aria2 action',
    options = options,
  }, function(choice)
    if choice == 'open' then
      open_task_file(task)
      return
    end
    if choice == 'pause' then
      api.pause(task.gid, function(_, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action('task paused')
      end)
      return
    end
    if choice == 'resume' then
      api.resume(task.gid, function(_, err)
        if err then
          show_error(err)
          return
        end
        refresh_after_action('task resumed')
      end)
      return
    end
    if choice == 'remove' then
      lc.confirm {
        title = 'Remove aria2 Task',
        prompt = 'Remove task "' .. task_name(task) .. '"?',
        on_confirm = function()
          api.remove(task.gid, task.status, function(_, err)
            if err then
              show_error(err)
              return
            end
            refresh_after_action('task removed')
          end)
        end,
      }
    end
  end)
  return true
end

local function show_hovered_task_actions()
  local task = hovered_task()
  if not task then return false end
  return task_actions(task)
end

function M.setup(opt)
  config.setup(opt)

  lc.keymap.set('main', '<enter>', function()
    local hovered = lc.api.page_get_hovered()
    if hovered and hovered.kind == 'section' then
      lc.cmd 'enter'
      return
    end
    if hovered and hovered.kind == 'task' then show_hovered_task_actions() end
  end)

  lc.keymap.set('main', 'a', function() show_hovered_task_actions() end)
  lc.keymap.set('main', 'o', function() open_hovered_file() end)
  lc.keymap.set('main', 'p', function() pause_hovered_task() end)
  lc.keymap.set('main', 'r', function() resume_hovered_task() end)
  lc.keymap.set('main', 'dd', function() remove_hovered_task() end)
  lc.keymap.set('main', 'n', add_download_from_input)
  lc.keymap.set('main', 'R', function()
    api.invalidate_cache()
    lc.notify 'aria2 cache invalidated'
    lc.cmd 'reload'
  end)
end

function M.list(path, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb {
      {
        key = 'not-configured',
        kind = 'info',
        display = line { span('Configure aria2 via setup() or ARIA2_RPC_URL', 'yellow') },
      },
    }
    return
  end

  if not path or #path == 0 then
    cb(section_entries())
    return
  end

  if SECTION_META[path[1]] then
    list_section(path[1], function(entries, list_err)
      if list_err then
        show_error(list_err)
        cb {
          {
            key = 'error',
            kind = 'info',
            display = line { span(list_err, 'red') },
          },
        }
        return
      end
      cb(entries)
    end)
    return
  end

  cb {}
end

function M.preview(entry, cb)
  local ok, err = api.ensure_configured()
  if not ok then
    cb(info_preview(err))
    return
  end

  if not entry then
    cb(info_preview 'No selection')
    return
  end

  if entry.kind == 'section' and entry.section then
    cb(section_preview(entry.section))
    return
  end

  if entry.kind == 'task' then
    cb(task_preview(entry))
    return
  end

  if entry.kind == 'info' then
    cb(info_preview(entry.key == 'error' and 'aria2 request failed' or 'No tasks'))
    return
  end

  cb(info_preview 'aria2')
end

return M
