local M = {}

local actions = require 'aria2.actions'
local config = require 'aria2.config'
local preview = require 'aria2.preview'

local function preview_method(renderer)
  return function(self, cb) cb(renderer(self)) end
end

local function section_keymap()
  local keymap = config.get().keymap
  return {
    [keymap.new] = { callback = actions.add_download_from_input, desc = 'add download' },
  }
end

local function task_keymap(self)
  local keymap = config.get().keymap
  local out = {
    [keymap.actions] = { callback = actions.task_actions, desc = 'task actions' },
    [keymap.new] = { callback = actions.add_download_from_input, desc = 'add download' },
  }
  if actions.can_open(self.task) then
    out[keymap.open_file] = { callback = actions.open_hovered_file, desc = 'open file' }
  end
  if actions.can_pause(self.task) then
    out[keymap.pause] = { callback = actions.pause_hovered_task, desc = 'pause task' }
  end
  if actions.can_resume(self.task) then
    out[keymap.resume] = { callback = actions.resume_hovered_task, desc = 'resume task' }
  end
  if actions.can_remove(self.task) then
    out[keymap.delete] = { callback = actions.remove_hovered_task, desc = 'remove task' }
  end
  return out
end

local section_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(preview.section_preview) end
    if key == 'keymap' then return section_keymap() end
  end,
}

local task_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(preview.task_preview) end
    if key == 'keymap' then return task_keymap(self) end
  end,
}

local info_mt = {
  __index = function(self, key)
    if key == 'preview' then return preview_method(preview.info_preview) end
    if key == 'keymap' then return section_keymap() end
  end,
}

local metatables = {
  section = section_mt,
  task = task_mt,
  info = info_mt,
}

function M.attach(entry)
  local mt = metatables[entry.kind]
  if mt then return setmetatable(entry, mt) end
  return entry
end

function M.attach_all(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    local mt = metatables[entry.kind]
    if mt then
      table.insert(out, setmetatable(entry, mt))
    else
      table.insert(out, entry)
    end
  end
  return out
end

return M
