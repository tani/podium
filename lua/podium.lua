#!/usr/bin/env lua

---@diagnostic disable: unused-local
---@diagnostic disable: unused-function

--[[
MIT License

Copyright (c) 2023 TANIGUCHI Masaya

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local M = {}
local _ -- dummy

---@alias PodiumElementKindInlineCmd
---| 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' | 'K' | 'L' | 'M'
---| 'N' | 'O' | 'P' | 'Q' | 'R' | 'S' | 'T' | 'U' | 'V' | 'W' | 'X' | 'Y' | 'Z'
---@alias PodiumElementKindBlockCmd
---| 'pod'
---| 'cut'
---| 'encoding'
---| 'over_unordered'
---| 'over_ordered'
---| 'item'
---| 'back_unordered'
---| 'back_ordered'
---| 'verb'
---| 'for'
---| 'head1'
---| 'head2'
---| 'head3'
---| 'head4'
---@alias PodiumElementKindInternalConstituent
---| 'list'
---| 'items'
---| 'itempart'
---| 'para'
---| 'text'
---| 'preamble'
---| 'postamble'
---| 'skip'
---@alias PodiumElementKind
---| PodiumElementKindBlockCmd
---| PodiumElementKindInlineCmd
---| PodiumElementKindInternalConstituent
---| string
---@class PodiumElement
---@field kind PodiumElementKind
---@field value string
---@field startIndex integer
---@field endIndex integer
---@field indentLevel integer

local PodiumElement = {}

---@param value string The content text of the element
---@param kind PodiumElementKind The kind of the element
---@param startIndex integer The index of the first character of the element in the source text.
---@param endIndex integer The index of the last character of the element in the source text.
---@param indentLevel integer (default: 0) The first character of the line following a line break is indented at this indent size.
---@return PodiumElement
function PodiumElement.new(kind, value, startIndex, endIndex, indentLevel)
  return setmetatable({
    kind = kind,
    value = value,
    startIndex = startIndex,
    endIndex = endIndex,
    indentLevel = indentLevel
  }, { __index = PodiumElement })
end

---@class PodiumState
---@field source string
---@field startIndex integer
---@field endIndex integer
---@field indentLevel integer

local PodiumState = {}

---@param source string
---@param startIndex integer (default: 1)
---@param endIndex integer (default: #source)
---@param indentLevel integer (default: 0)
function PodiumState.new(source, startIndex, endIndex, indentLevel)
  return setmetatable({
    source = source,
    startIndex = startIndex or 1,
    endIndex = endIndex or #source,
    indentLevel = indentLevel or 0,
  }, { __index = PodiumState })
end

---@param t table
---@param indent? number  always 0
local function debug(t, indent)
  indent = indent or 0
  for k, v in pairs(t) do
    if type(v) == "table" then
      print(string.rep(" ", indent) .. k .. ":")
      debug(v, indent + 2)
    else
      print(string.rep(" ", indent) .. k .. ": " .. tostring(v))
    end
  end
end

---@generic T
---@param t T[]
---@param i? integer
---@param j? integer
---@return T[]
local function slice(t, i, j)
  i = i and i > 0 and i or 1
  j = j and j <= #t and j or #t
  local r = {}
  for k = i, j do
    table.insert(r, t[k])
  end
  return r
end

---@generic T
---@param t T[]
---@param ... T[]
---@return T[]
local function append(t, ...)
  local r = {}
  for _, v in ipairs(t) do
    table.insert(r, v)
  end
  for _, s in ipairs({ ... }) do
    for _, v in ipairs(s) do
      table.insert(r, v)
    end
  end
  return r
end

---@param source string
---@return string "\r"|"\n"|"\r\n"
local function guessNewline(source)
  local i = 1
  while i <= #source do
    local c = source:sub(i, i)
    if c == "\n" then
      return "\n"
    elseif c == "\r" then
      if source:sub(i + 1, i + 1) == "\n" then
        return "\r\n"
      else
        return "\r"
      end
    end
    i = i + 1
  end
  return "\n"
end

---@param state PodiumState
---@return PodiumState
local function trimBlank(state)
  local i = state.startIndex
  while i <= state.endIndex do
    if state.source:sub(i, i):match("%s") then
      i = i + 1
    else
      break
    end
  end
  local j = state.endIndex
  while j >= i do
    if state.source:sub(j, j):match("%s") then
      j = j - 1
    else
      break
    end
  end
  return PodiumState.new(state.source, i, j, state.indentLevel)
end

---@param state PodiumState
---@return string[]
local function splitLines(state)
  ---@type string[]
  local lines = {}
  local i = state.startIndex
  while i <= state.endIndex do
    local j = state.source:sub(1, state.endIndex):find("[\r\n]", i)
    if j == nil then
      table.insert(lines, state.source:sub(i, state.endIndex))
      i = state.endIndex + 1
    else
      if state.source:sub(j, j) == "\r" then
        if state.source:sub(j + 1, j + 1) == "\n" then
          j = j + 1
        end
      end
      table.insert(lines, state.source:sub(i, j))
      i = j + 1
    end
  end
  return lines
end

---@param source string
---@return table<string, string>
local function parseFrontMatter(source)
  ---@type table<string, string>
  local frontmatter = {}
  local lines = splitLines(PodiumState.new(source, 1, #source, 0))
  local inside = false
  for _, line in ipairs(lines) do
    if inside then
      if line:match("^%s*---%s*$") then
        break
      else
        local key, value = line:match("^%s*(%w-)%s*:%s*(.-)%s*$")
        if key then
          frontmatter[key] = value
        end
      end
    else
      if line:match("^%s*---%s*$") then
        inside = true
      end
    end
  end
  return frontmatter
end

---@param source string
---@param startIndex integer
---@return integer,integer
local function indexToRowCol(source, startIndex)
  local row = 1
  local col = 1
  local i = 1
  while i < startIndex do
    local c = source:sub(i, i)
    if c == "\n" then
      row = row + 1
      col = 1
    elseif c == "\r" then
      row = row + 1
      col = 1
      if source:sub(i + 1, i + 1) == "\n" then
        i = i + 1
      end
    else
      col = col + 1
    end
    i = i + 1
  end
  return row, col
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return integer,integer,integer,integer
local function findInline(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  for b_cmd = startIndex, endIndex do
    if source:sub(b_cmd, b_cmd):match("[A-Z]") then
      if source:sub(b_cmd + 1, b_cmd + 1) == "<" then
        local count = 1
        local space = ""
        local i = b_cmd + 2
        local b_arg, e_arg = nil, nil
        while i <= endIndex do
          if source:sub(i, i) == "<" then
            count = count + 1
            i = i + 1
          elseif source:sub(i, i):match("%s") then
            b_arg = i + 1
            space = "%s"
            break
          else
            b_arg = b_cmd + 2
            count = 1
            break
          end
        end
        if i > endIndex then
          local row, col = indexToRowCol(source, b_cmd)
          error(
            "ERROR:"
              .. row
              .. ":"
              .. col
              .. ": "
              .. "Missing closing brackets '<"
              .. string.rep(">", count)
              .. "'"
          )
        end
        local angles = space .. string.rep(">", count)
        while i <= endIndex do
          if source:sub(i, i + #angles - 1):match(angles) then
            e_arg = i - 1
            break
          end
          if source:sub(i, i) == "<" then
            if source:sub(i - 1, i - 1):match("[A-Z]") then
              _, _, _, i = findInline(source, i - 1)
            end
          end
          i = i + 1
        end
        if i > endIndex then
          local row, col = indexToRowCol(source, b_cmd)
          error(
            "Missing closing brackets '"
              .. string.rep(">", count)
              .. "':"
              .. row
              .. ":"
              .. col
              .. ": "
              .. source:sub(b_cmd, b_cmd + count)
          )
        end
        return b_cmd, b_arg, e_arg, i + #angles - 1
      end
    end
  end
  error("Failed to find inline command")
end

---@type PodiumConvertElementSource
local function splitParagraphs(state)
  local state_list = 0
  local state_para = 0
  local state_verb = 0
  local state_block = 0
  local block_name = ""
  local state_cmd = 0
  local cmd_name = ""
  ---@type PodiumElement[]
  local paragraphs = {}
  ---@type string[]
  local lines = {}
  local startIndex = state.startIndex
  local endIndex = state.startIndex
  for _, line in ipairs(splitLines(state)) do
    endIndex = endIndex + #line
    if state_list > 0 then
      table.insert(lines, line)
      if line:match("^=over") then
        state_list = state_list + 1
      elseif line:match("^=back") then
        state_list = state_list - 1
      elseif state_list == 1 and line:match("^%s+$") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            "list",
            table.concat(lines),
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
        state_list = 0
        lines = {}
      end
    elseif state_para > 0 then
      table.insert(lines, line)
      if state_para == 1 and line:match("^%s+$") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            "para",
            table.concat(lines),
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
        state_para = 0
        lines = {}
      end
    elseif state_verb > 0 then
      if state_verb == 1 and line:match("^%S") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            "verb",
            table.concat(lines),
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
        lines = { line }
        state_verb = 0
        if line:match("^=over") then
          state_list = 2
        elseif line:match("^=begin") then
          state_block = 2
          block_name = line:match("^=begin%s+(%S+)")
        elseif line:match("^=") then
          state_cmd = 1
          cmd_name = line:match("^=(%S+)")
        else
          state_para = 1
        end
      else
        table.insert(lines, line)
        if line:match("^%s+$") then
          state_verb = 1
        end
      end
    elseif state_block > 0 then
      table.insert(lines, line)
      if line:match("^=end%s+" .. block_name) then
        state_block = 1
      end
      if state_block == 1 and line:match("^%s+$") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            block_name,
            table.concat(lines),
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
        lines = {}
        state_block = 0
      end
    elseif state_cmd > 0 then
      table.insert(lines, line)
      if state_cmd == 1 and line:match("^%s+$") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            cmd_name,
            table.concat(lines),
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
        lines = {}
        state_cmd = 0
      end
    else
      if line:match("^%s+$") then
        table.insert(
          paragraphs,
          PodiumElement.new(
            "skip",
            line,
            startIndex,
            endIndex - 1,
            state.indentLevel
          )
        )
        startIndex = endIndex
      elseif line:match("^=over") then
        table.insert(lines, line)
        state_list = 2
      elseif line:match("^=begin") then
        table.insert(lines, line)
        state_block = 2
        block_name = line:match("^=begin%s+(%S+)")
      elseif line:match("^[ \t]") then
        table.insert(lines, line)
        state_verb = 2
      elseif line:match("^=") then
        table.insert(lines, line)
        state_cmd = 1
        cmd_name = line:match("^=(%S+)")
      else
        table.insert(lines, line)
        state_para = 1
      end
    end
  end
  if #lines > 0 then
    if state_list > 0 then
      table.insert(
        paragraphs,
        PodiumElement.new(
          "list",
          table.concat(lines),
          startIndex,
          endIndex - 1,
          state.indentLevel
        )
      )
      startIndex = endIndex
    elseif state_para > 0 then
      table.insert(
        paragraphs,
        PodiumElement.new(
          "para",
          table.concat(lines),
          startIndex,
          endIndex - 1,
          state.indentLevel
        )
      )
      startIndex = endIndex
    elseif state_verb > 0 then
      table.insert(
        paragraphs,
        PodiumElement.new(
          "verb",
          table.concat(lines),
          startIndex,
          endIndex - 1,
          state.indentLevel
        )
      )
      startIndex = endIndex
    elseif state_block > 0 then
      table.insert(
        paragraphs,
        PodiumElement.new(
          block_name,
          table.concat(lines),
          startIndex,
          endIndex - 1,
          state.indentLevel
        )
      )
      startIndex = endIndex
    elseif state_cmd > 0 then
      table.insert(
        paragraphs,
        PodiumElement.new(
          cmd_name,
          table.concat(lines),
          startIndex,
          endIndex - 1,
          state.indentLevel
        )
      )
      startIndex = endIndex
    end
  end
  return paragraphs
end

---@type PodiumConvertElementSource
local function splitItem(state)
  local itemState = 0
  ---@type string[]
  local lines = {}
  ---@type PodiumElement[]
  local parts = {}
  local startIndex = state.startIndex
  for _, line in ipairs(splitLines(state)) do
    if itemState == 0 then
      if line:match("^=over") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          parts,
          PodiumElement.new(
            "itempart",
            table.concat(lines),
            startIndex,
            endIndex,
            state.indentLevel
          )
        )
        startIndex = endIndex + 1
        itemState = itemState + 2
        lines = { line }
      else
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
      if line:match("^=over") then
        itemState = itemState + 1
      elseif line:match("^=back") then
        itemState = itemState - 1
      elseif itemState == 1 and line:match("^%s+$") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          parts,
          PodiumElement.new(
            "list",
            table.concat(lines),
            startIndex,
            endIndex,
            state.indentLevel
          )
        )
        startIndex = endIndex + 1
        lines = {}
        itemState = 0
      end
    end
  end
  if #lines > 0 then
    if itemState > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        parts,
        PodiumElement.new(
          "list",
          table.concat(lines),
          startIndex,
          endIndex,
          state.indentLevel
        )
      )
      startIndex = endIndex + 1
    else
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        parts,
        PodiumElement.new(
          "itempart",
          table.concat(lines),
          startIndex,
          endIndex,
          state.indentLevel
        )
      )
      startIndex = endIndex + 1
    end
  end
  return parts
end

---@type PodiumConvertElementSource
local function splitItems(state)
  ---@type PodiumElement[]
  local items = {}
  ---@type "nonitems"|"items"
  local itemsState = "nonitems"
  local allLines = splitLines(state)
  ---@type string[]
  local lines = {}
  local depth = 0
  local index = 1
  local startIndex = state.startIndex
  while index <= #allLines do
    local line = allLines[index]
    if itemsState == "nonitems" then
      if line:match("^=item") then
        if depth == 0 then
          if #lines > 0 then
            local row, col = indexToRowCol(state.source, state.startIndex)
            error(
              "ERROR:"
                .. row
                .. ":"
                .. col
                .. ": non-item lines should not precede an item"
            )
          end
          lines = { line }
          itemsState = "items"
          index = index + 1
        else
          index = index + 1
        end
      elseif line:match("^=over") then
        depth = depth + 1
        index = index + 1
      elseif line:match("^=back") then
        depth = depth - 1
        index = index + 1
      else
        index = index + 1
      end
    elseif itemsState == "items" then
      if line:match("^=item") then
        if depth == 0 then
          local endIndex = startIndex + #table.concat(lines) - 1
          table.insert(
            items,
            PodiumElement.new(
              "item",
              table.concat(lines),
              startIndex,
              endIndex,
              state.indentLevel
            )
          )
          startIndex = endIndex + 1
          lines = { line }
          index = index + 1
        else
          table.insert(lines, line)
          index = index + 1
        end
      elseif line:match("^=over") then
        depth = depth + 1
        table.insert(lines, line)
        index = index + 1
      elseif line:match("^=back") then
        depth = depth - 1
        table.insert(lines, line)
        index = index + 1
      else
        table.insert(lines, line)
        index = index + 1
      end
    end
  end
  if itemsState == "items" then
    local endIndex = startIndex + #table.concat(lines) - 1
    table.insert(
      items,
      PodiumElement.new(
        "item",
        table.concat(lines),
        startIndex,
        endIndex,
        state.indentLevel
      )
    )
    startIndex = endIndex + 1
  else
    return splitParagraphs(state)
  end
  return items
end

---@type PodiumConvertElementSource
local function splitTokens(state)
  ---@type PodiumElement[]
  local tokens = {}
  local i = state.startIndex
  while i <= state.endIndex do
    local ok, b_cmd, _, _, e_cmd =
      pcall(findInline, state.source, i, state.endIndex)
    if ok then
      table.insert(
        tokens,
        PodiumElement.new(
          "text",
          state.source:sub(i, b_cmd - 1),
          i,
          b_cmd - 1,
          state.indentLevel
        )
      )
      table.insert(
        tokens,
        PodiumElement.new(
          state.source:sub(b_cmd, b_cmd),
          state.source:sub(b_cmd, e_cmd),
          b_cmd,
          e_cmd,
          state.indentLevel
        )
      )
      i = e_cmd + 1
    else
      table.insert(
        tokens,
        PodiumElement.new(
          "text",
          state.source:sub(i, state.endIndex),
          i,
          state.endIndex,
          state.indentLevel
        )
      )
      i = state.endIndex + 1
    end
  end
  return tokens
end

---@type PodiumConvertElementSource
local function splitList(state)
  ---@type 'over' | 'items' | 'back'
  local listState = "over"
  local lines = splitLines(state)
  local list_type = "unordered"
  ---@type string[]
  local over_lines = {}
  ---@type string[]
  local items_lines = {}
  local items_depth = 0
  ---@type string[]
  local back_lines = {}
  local index = 1
  while index <= #lines do
    local line = lines[index]
    if listState == "over" then
      table.insert(over_lines, line)
      if line:match("^%s*$") then
        listState = "items"
      end
      index = index + 1
    elseif listState == "items" then
      if line:match("^=over") then
        items_depth = items_depth + 1
        table.insert(items_lines, line)
        index = index + 1
      elseif line:match("^=back") then
        items_depth = items_depth - 1
        if items_depth >= 0 then
          table.insert(items_lines, line)
          index = index + 1
        else
          listState = "back"
        end
      elseif line:match("^=item") then
        if items_depth == 0 then
          if line:match("^=item%s*%d+") then
            list_type = "ordered"
          end
        end
        table.insert(items_lines, line)
        index = index + 1
      else
        table.insert(items_lines, line)
        index = index + 1
      end
    else
      table.insert(back_lines, line)
      index = index + 1
    end
  end
  local over_endIndex = state.startIndex
  for _, line in ipairs(over_lines) do
    over_endIndex = over_endIndex + #line
  end
  over_endIndex = over_endIndex - 1
  local items_startIndex = over_endIndex + 1
  local items_endIndex = items_startIndex
  for _, line in ipairs(items_lines) do
    items_endIndex = items_endIndex + #line
  end
  items_endIndex = items_endIndex - 1
  local back_startIndex = items_endIndex + 1
  local back_endIndex = back_startIndex
  for _, line in ipairs(back_lines) do
    back_endIndex = back_endIndex + #line
  end
  back_endIndex = back_endIndex - 1
  local indentLevel = tonumber(table.concat(over_lines):match("(%d+)") or "4")
  return {
    PodiumElement.new(
      "over_" .. list_type,
      table.concat(over_lines),
      state.startIndex,
      over_endIndex,
      (state.indentLevel + indentLevel)
    ),
    PodiumElement.new(
      "items",
      table.concat(items_lines),
      items_startIndex,
      items_endIndex,
      (state.indentLevel + indentLevel)
    ),
    PodiumElement.new(
      "back_" .. list_type,
      table.concat(back_lines),
      back_startIndex,
      back_endIndex,
      state.indentLevel
    ),
  }
end

---@param source string
---@param target PodiumConverter
local function process(source, target)
  local elements = splitParagraphs(PodiumState.new(source, 1, #source, 0))
  local nl = guessNewline(source)
  local shouldProcess = false
  local i = 1
  while i <= #elements do
    local element = elements[i]
    if element.kind == "pod" then
      shouldProcess = true
    end
    if shouldProcess then
      if element.kind == "text" then
        i = i + 1
      else
        elements = append(
          slice(elements, 1, i - 1),
          target[element.kind](
            PodiumState.new(source, element.startIndex, element.endIndex, element.indentLevel)
          ),
          slice(elements, i + 1)
        )
      end
    else
      elements = append(slice(elements, 1, i - 1), {
        PodiumElement.new(
          "skip",
          source:sub(element.startIndex, element.endIndex),
          element.startIndex,
          element.endIndex,
          0
        ),
      }, slice(elements, i + 1))
      i = i + 1
    end
    if element.kind == "cut" then
      shouldProcess = false
    end
  end
  elements = append(
    target["preamble"](PodiumState.new(source, 1, #source, 0)),
    elements,
    target["postamble"](PodiumState.new(source, 1, #source, 0))
  )
  local output = ""
  for _, element in ipairs(elements) do
    if element.kind ~= "skip" then
      local text = element.value:gsub(nl, nl .. (" "):rep(element.indentLevel))
      output = output .. text
    end
  end
  return output
end

---@alias PodiumConvertElementSource fun(state: PodiumState): PodiumElement[]
---@alias PodiumConverter table<PodiumElementKind, PodiumConvertElementSource>

---@param tbl PodiumConverter
---@return PodiumConverter
local function rules(tbl)
  return setmetatable(tbl, {
    __index = function(_table, _key)
      return function(_source, _startIndex, _endIndex)
        return {}
      end
    end,
  })
end

---@param value string
---@param indentLevel number
---@return PodiumElement
local function parsed_token(value, indentLevel)
  return PodiumElement.new("text", value, -1, -1, indentLevel)
end

local html = rules({
  preamble = function(state)
    return {}
  end,
  postamble = function(state)
    return {}
  end,
  head1 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<h1>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</h1>" .. nl, state.indentLevel) }
    )
  end,
  head2 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<h2>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</h2>" .. nl, state.indentLevel) }
    )
  end,
  head3 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<h3>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</h3>" .. nl, state.indentLevel) }
    )
  end,
  head4 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<h4>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</h4>" .. nl, state.indentLevel) }
    )
  end,
  para = function(state)
    local nl = guessNewline(state.source)
    state = trimBlank(state)
    return append(
      { parsed_token("<p>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</p>" .. nl, state.indentLevel) }
    )
  end,
  over_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl .. "<ul>" .. nl, state.indentLevel) }
  end,
  over_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl .. "<ol>" .. nl, state.indentLevel) }
  end,
  back_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token("</ul>" .. nl .. nl, state.indentLevel) }
  end,
  back_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token("</ol>" .. nl .. nl, state.indentLevel) }
  end,
  cut = function(state)
    return {}
  end,
  pod = function(state)
    return {}
  end,
  verb = function(state)
    local nl = guessNewline(state.source)
    return {
      parsed_token("<pre><code>" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("</code></pre>" .. nl, state.indentLevel),
    }
  end,
  html = function(state)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(state)) do
      if blockState == 0 then
        if line:match("^=begin") then
          blockState = 1
        elseif line:match("^=end") then
          blockState = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(table.concat(lines), state.indentLevel) }
  end,
  item = function(state)
    local nl = guessNewline(state.source)
    _, state.startIndex = state.source
      :sub(1, state.endIndex)
      :find("^=item%s*[*0-9]*%.?.", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<li>", state.indentLevel) },
      splitItem(state),
      { parsed_token("</li>" .. nl, state.indentLevel) }
    )
  end,
  ["for"] = function(state)
    local nl = guessNewline(state.source)
    _, state.startIndex =
      state.source:sub(1, state.endIndex):find("=for%s+%S+%s", state.startIndex)
    return {
      parsed_token("<pre><code>" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("</code></pre>" .. nl, state.indentLevel),
    }
  end,
  list = function(state)
    return splitList(state)
  end,
  items = function(state)
    return splitItems(state)
  end,
  itempart = function(state)
    return splitTokens(state)
  end,
  I = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<em>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</em>", state.indentLevel) }
    )
  end,
  B = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<strong>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</strong>", state.indentLevel) }
    )
  end,
  C = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("<code>", state.indentLevel) },
      splitTokens(state),
      { parsed_token("</code>", state.indentLevel) }
    )
  end,
  L = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    local b, e =
      state.source:sub(1, state.endIndex):find("[^|]*|", state.startIndex)
    if b then
      return append(
        { parsed_token('<a href="', state.indentLevel) },
        splitTokens(PodiumState.new(state.source, e + 1, state.endIndex, state.indentLevel)),
        { parsed_token('">', state.indentLevel) },
        splitTokens(PodiumState.new(state.source, b, e - 1, state.indentLevel)),
        { parsed_token("</a>", state.indentLevel) }
      )
    else
      return append(
        { parsed_token('<a href="', state.indentLevel) },
        splitTokens(state),
        { parsed_token('">', state.indentLevel) },
        splitTokens(state),
        { parsed_token("</a>", state.indentLevel) }
      )
    end
  end,
  E = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    local arg = state.source:sub(state.startIndex, state.endIndex)
    return { parsed_token("&" .. arg .. ";", state.indentLevel) }
  end,
  X = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token('<a name="', state.indentLevel) },
      splitTokens(state),
      { parsed_token('"></a>', state.indentLevel) }
    )
  end,
  Z = function(state)
    return {}
  end,
})

local markdown = rules({
  preamble = function(state)
    return {}
  end,
  postamble = function(state)
    return {}
  end,
  head1 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("# ", state.indentLevel) },
      splitTokens(state),
      { parsed_token(nl .. nl, state.indentLevel) }
    )
  end,
  head2 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("## ", state.indentLevel) },
      splitTokens(state),
      { parsed_token(nl .. nl, state.indentLevel) }
    )
  end,
  head3 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("### ", state.indentLevel) },
      splitTokens(state),
      { parsed_token(nl .. nl, state.indentLevel) }
    )
  end,
  head4 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("#### ", state.indentLevel) },
      splitTokens(state),
      { parsed_token(nl .. nl, state.indentLevel) }
    )
  end,
  para = function(state)
    local nl = guessNewline(state.source)
    state = trimBlank(state)
    return append(splitTokens(state), { parsed_token(nl .. nl, state.indentLevel) })
  end,
  over_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  over_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  back_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  back_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  cut = function(state)
    return {}
  end,
  pod = function(state)
    return {}
  end,
  verb = function(state)
    local nl = guessNewline(state.source)
    return {
      parsed_token("```" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("```" .. nl .. nl, state.indentLevel),
    }
  end,
  html = function(state)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(state)) do
      if blockState == 0 then
        if line:match("^=begin") then
          blockState = 1
        elseif line:match("^=end") then
          blockState = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(table.concat(lines), state.indentLevel) }
  end,
  item = function(state)
    local nl = guessNewline(state.source)
    local bullet = "-"
    if state.source:sub(1, state.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = state.source
        :sub(1, state.endIndex)
        :find("^=item%s*([0-9]+%.?)", state.startIndex)
    end
    _, state.startIndex = state.source
      :sub(1, state.endIndex)
      :find("^=item%s*[*0-9]*%.?.", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token(bullet .. " ", state.indentLevel) },
      splitItem(state),
      { parsed_token(nl, state.indentLevel) }
    )
  end,
  ["for"] = function(state)
    _, state.startIndex =
      state.source:sub(1, state.endIndex):find("=for%s+%S+%s", state.startIndex)
    local nl = guessNewline(state.source)
    return {
      parsed_token("```" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("```" .. nl, state.indentLevel),
    }
  end,
  list = function(state)
    return splitList(state)
  end,
  items = function(state)
    return splitItems(state)
  end,
  itempart = function(state)
    return splitTokens(state)
  end,
  I = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("*", state.indentLevel) },
      splitTokens(state),
      { parsed_token("*", state.indentLevel) }
    )
  end,
  B = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("**", state.indentLevel) },
      splitTokens(state),
      { parsed_token("**", state.indentLevel) }
    )
  end,
  C = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("`", state.indentLevel) },
      splitTokens(state),
      { parsed_token("`", state.indentLevel) }
    )
  end,
  L = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    local b, e =
      state.source:sub(1, state.endIndex):find("[^|]*|", state.startIndex)
    if b then
      return append(
        { parsed_token("[", state.indentLevel) },
        splitTokens(PodiumState.new(state.source, b, e - 1, state.endIndex)),
        { parsed_token("](", state.indentLevel) },
        splitTokens(PodiumState.new(state.source, e + 1, state.endIndex, state.endIndex)),
        { parsed_token(")", state.indentLevel) }
      )
    else
      return append(
        { parsed_token("[", state.indentLevel) },
        splitTokens(state),
        { parsed_token("](", state.indentLevel) },
        splitTokens(state),
        { parsed_token(")", state.indentLevel) }
      )
    end
  end,
  E = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    if state.source:sub(state.startIndex, state.endIndex) == "lt" then
      return { parsed_token("<", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "gt" then
      return { parsed_token(">", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "verbar" then
      return { parsed_token("|", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "sol" then
      return { parsed_token("/", state.indentLevel) }
    else
      return {
        parsed_token(
          "&" .. state.source:sub(state.startIndex, state.endIndex) .. ";"
        , state.indentLevel),
      }
    end
  end,
  Z = function(state)
    return {}
  end,
})

---@type PodiumConvertElementSource
local function vimdoc_head(state)
  local nl = guessNewline(state.source)
  state.startIndex =
    state.source:sub(1, state.endIndex):find("%s", state.startIndex)
  state = trimBlank(state)
  local tokens = splitTokens(state)
  ---@type PodiumElement[]
  local tags = {}
  local padding = 78
  for i, token in ipairs(tokens) do
    if token.kind == "X" then
      padding = padding - #token.value
      table.remove(tokens, i)
      table.insert(tags, token)
    end
  end
  if #tags > 0 then
    return append(
      tokens,
      { parsed_token("~" .. nl .. string.rep(" ", padding), state.indentLevel) },
      tags,
      { parsed_token(nl .. nl, state.indentLevel) }
    )
  else
    return append(tokens, { parsed_token("~" .. nl .. nl, state.indentLevel) })
  end
end

local vimdoc = rules({
  preamble = function(state)
    local nl = guessNewline(state.source)
    local frontmatter = parseFrontMatter(state.source)
    local filename = frontmatter.name .. ".txt"
    local description = frontmatter.description
    local spaces = string.rep(" ", 78 - #filename - #description - #nl)
    return { parsed_token(filename .. spaces .. description .. nl, state.indentLevel) }
  end,
  postamble = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl .. "vim:tw=78:ts=8:noet:ft=help:norl:" .. nl, state.indentLevel) }
  end,
  head1 = function(state)
    local nl = guessNewline(state.source)
    return append(
      { parsed_token(string.rep("=", 78 - #nl) .. nl, state.indentLevel) },
      vimdoc_head(state)
    )
  end,
  head2 = vimdoc_head,
  head3 = vimdoc_head,
  head4 = vimdoc_head,
  para = function(state)
    local nl = guessNewline(state.source)
    state = trimBlank(state)
    local tokens = splitTokens(state)
    return append(tokens, { parsed_token(nl .. nl, state.indentLevel) })
  end,
  over_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  over_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  back_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  back_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl, state.indentLevel) }
  end,
  cut = function(state)
    return {}
  end,
  pod = function(state)
    return {}
  end,
  verb = function(state)
    local nl = guessNewline(state.source)
    return {
      parsed_token(">" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("<" .. nl .. nl, state.indentLevel),
    }
  end,
  vimdoc = function(state)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(state)) do
      if blockState == 0 then
        if line:match("^=begin") then
          blockState = 1
        elseif line:match("^=end") then
          blockState = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(table.concat(lines), state.indentLevel) }
  end,
  item = function(state)
    local nl = guessNewline(state.source)
    local bullet = "-"
    if state.source:sub(1, state.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = state.source
        :sub(1, state.endIndex)
        :find("^=item%s*([0-9]+%.?)", state.startIndex)
    end
    _, state.startIndex = state.source
      :sub(1, state.endIndex)
      :find("^=item%s*[*0-9]*%.?.", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token(bullet .. " ", state.indentLevel) },
      splitItem(state),
      { parsed_token(nl, state.indentLevel) }
    )
  end,
  ["for"] = function(state)
    _, state.startIndex =
      state.source:sub(1, state.endIndex):find("=for%s+%S+%s", state.startIndex)
    local nl = guessNewline(state.source)
    return {
      parsed_token("<" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token(">" .. nl .. nl, state.indentLevel),
    }
  end,
  list = function(state)
    return splitList(state)
  end,
  items = function(state)
    return splitItems(state)
  end,
  itempart = function(state)
    return splitTokens(state)
  end,
  C = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("`", state.indentLevel) },
      splitTokens(state),
      { parsed_token("`", state.indentLevel) }
    )
  end,
  O = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("'", state.indentLevel) },
      splitTokens(state),
      { parsed_token("'", state.indentLevel) }
    )
  end,
  L = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    local b, e =
      state.source:sub(1, state.endIndex):find("[^|]*|", state.startIndex)
    if b then
      return append(
        splitTokens(PodiumState.new(state.source, b, e - 1, state.startIndex)),
        { parsed_token(" |", state.indentLevel) },
        splitTokens(PodiumState.new(state.source, e + 1, state.endIndex, e + 1)),
        { parsed_token("|", state.indentLevel) }
      )
    else
      return append(
        { parsed_token("|", state.indentLevel) },
        splitTokens(state),
        { parsed_token("|", state.indentLevel) }
      )
    end
  end,
  X = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("*", state.indentLevel) },
      splitTokens(state),
      { parsed_token("*", state.indentLevel) }
    )
  end,
  E = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    if state.source:sub(state.startIndex, state.endIndex) == "lt" then
      return { parsed_token("<", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "gt" then
      return { parsed_token(">", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "verbar" then
      return { parsed_token("|", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "sol" then
      return { parsed_token("/", state.indentLevel) }
    else
      return {
        parsed_token(
          "&" .. state.source:sub(state.startIndex, state.endIndex) .. ";"
        , state.indentLevel),
      }
    end
  end,
  Z = function(state)
    return {}
  end,
})

local latex = rules({
  preamble = function(state)
    return {}
  end,
  postamble = function(state)
    return {}
  end,
  head1 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\section{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}" .. nl, state.indentLevel) }
    )
  end,
  head2 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\subsection{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}" .. nl, state.indentLevel) }
    )
  end,
  head3 = function(state)
    local nl = guessNewline(state.source)
    state.startIndex =
      state.source:sub(1, state.endIndex):find("%s", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\subsubsection{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}" .. nl, state.indentLevel) }
    )
  end,
  para = function(state)
    local nl = guessNewline(state.source)
    state = trimBlank(state)
    return append(splitTokens(state), { parsed_token(nl, state.indentLevel) })
  end,
  over_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl .. "\\begin{itemize}" .. nl, state.indentLevel) }
  end,
  over_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token(nl .. "\\begin{enumerate}" .. nl, state.indentLevel) }
  end,
  back_unordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token("\\end{itemize}" .. nl, state.indentLevel) }
  end,
  back_ordered = function(state)
    local nl = guessNewline(state.source)
    return { parsed_token("\\end{enumerate}" .. nl, state.indentLevel) }
  end,
  cut = function(state)
    return {}
  end,
  pod = function(state)
    return {}
  end,
  verb = function(state)
    local nl = guessNewline(state.source)
    return {
      parsed_token("\\begin{verbatim}" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("\\end{verbatim}" .. nl, state.indentLevel),
    }
  end,
  latex = function(state)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(state)) do
      if blockState == 0 then
        if line:match("^=begin") then
          blockState = 1
        elseif line:match("^=end") then
          blockState = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(table.concat(lines), state.indentLevel) }
  end,
  item = function(state)
    local nl = guessNewline(state.source)
    _, state.startIndex = state.source
      :sub(1, state.endIndex)
      :find("^=item%s*[*0-9]*%.?.", state.startIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\item ", state.indentLevel) },
      splitItem(state),
      { parsed_token(nl, state.indentLevel) }
    )
  end,
  ["for"] = function(state)
    local nl = guessNewline(state.source)
    _, state.startIndex =
      state.source:sub(1, state.endIndex):find("=for%s+%S+%s", state.startIndex)
    return {
      parsed_token("\\begin{verbatim}" .. nl, state.indentLevel),
      parsed_token(state.source:sub(state.startIndex, state.endIndex), state.indentLevel),
      parsed_token("\\end{verbatim}" .. nl, state.indentLevel),
    }
  end,
  list = function(state)
    return splitList(state)
  end,
  items = function(state)
    return splitItems(state)
  end,
  itempart = function(state)
    return splitTokens(state)
  end,
  I = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\textit{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}", state.indentLevel) }
    )
  end,
  B = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\textbf{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}", state.indentLevel) }
    )
  end,
  C = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\verb|", state.indentLevel) },
      splitTokens(state),
      { parsed_token("|", state.indentLevel) }
    )
  end,
  L = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    local b, e =
      state.source:sub(1, state.endIndex):find("[^|]*|", state.startIndex)
    if b then
      return append(
        { parsed_token("\\href{", state.indentLevel) },
        splitTokens(PodiumState.new(state.source, e + 1, state.endIndex, state.indentLevel)),
        { parsed_token("}{", state.indentLevel) },
        splitTokens(PodiumState.new(state.source, b, e - 1, state.indentLevel)),
        { parsed_token("}", state.indentLevel) }
      )
    elseif
      state.source:sub(state.startIndex, state.endIndex):match("^https?://")
    then
      return append(
        { parsed_token("\\url{", state.indentLevel) },
        splitTokens(state),
        { parsed_token("}", state.indentLevel) }
      )
    else
      return {
        { parsed_token("\\ref{", state.indentLevel) },
        splitTokens(state),
        { parsed_token("}", state.indentLevel) },
      }
    end
  end,
  E = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    if state.source:sub(state.startIndex, state.endIndex) == "lt" then
      return { parsed_token("<", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "gt" then
      return { parsed_token(">", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "verbar" then
      return { parsed_token("|", state.indentLevel) }
    elseif state.source:sub(state.startIndex, state.endIndex) == "sol" then
      return { parsed_token("/", state.indentLevel) }
    else
      return {
        parsed_token("\\texttt{", state.indentLevel),
        splitTokens(state),
        parsed_token("}", state.indentLevel),
      }
    end
  end,
  X = function(state)
    _, state.startIndex, state.endIndex, _ =
      findInline(state.source, state.startIndex, state.endIndex)
    state = trimBlank(state)
    return append(
      { parsed_token("\\label{", state.indentLevel) },
      splitTokens(state),
      { parsed_token("}", state.indentLevel) }
    )
  end,
  Z = function(state)
    return {}
  end,
})

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return string
function M.arg(source, startIndex, endIndex)
  local _, b, e, _ = findInline(source, startIndex, endIndex)
  if b then
    return source:sub(b, e)
  else
    return ""
  end
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return string
function M.body(source, startIndex, endIndex)
  local nl = guessNewline(source)
  local _, e = source:sub(1, endIndex):find("^=begin.*" .. nl, startIndex)
  local _, f = source:sub(1, endIndex):find(nl .. "=end.*$", startIndex)
  return source:sub(e + 1, f - 1)
end

M.PodiumState = PodiumState
M.PodiumElement = PodiumElement
M.findInline = findInline
M.splitLines = splitLines
M.splitParagraphs = splitParagraphs
M.splitItem = splitItem
M.splitItems = splitItems
M.findInline = findInline
M.splitTokens = splitTokens
M.splitList = splitList
M.process = process
M.html = html
M.markdown = markdown
M.latex = latex
M.vimdoc = vimdoc

if _G["SOURCE"] and _G["TARGET"] then
  return M.process(_G["SOURCE"], M[_G["TARGET"]])
end

if #arg > 0 and arg[0]:match("podium") then
  local input
  if arg[2] then
    local ifile = io.open(arg[2], "r")
    if not ifile then
      error("cannot open file: " .. arg[2])
    end
    input = ifile:read("*a")
  else
    input = io.read("*a")
  end
  local output = M.process(input, M[arg[1]])
  if arg[3] then
    local ofile = io.open(arg[3], "w")
    if not ofile then
      error("cannot open file: " .. arg[3])
    end
    ofile:write(output)
  else
    io.write(output)
  end
end

return M
