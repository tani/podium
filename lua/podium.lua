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
---@alias PodiumElementKindBlockCmd -- All block commands defined in POD spec
---| 'pod'
---| 'cut'
---| 'encoding'
---| 'over'
---| 'item'
---| 'back'
---| 'verb'
---| 'for'
---| 'head1'
---| 'head2'
---| 'head3'
---| 'head4'
---@alias PodiumElementKindInternalConstituent -- All internal constituents
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
---| string if you want to add custom block comando, use this type
---@class PodiumElement
---@field kind PodiumElementKind The kind of the element
---@field value string The content text of the element
---@field source string The source text of the element
---@field startIndex integer The index of the first character of the element in the source text.
---@field endIndex integer The index of the last character of the element in the source text.
---@field indentLevel integer The first character of the line following a line break is indented at this indent size.
---@field [string] any extra properties: listStyle and so on.
local PodiumElement = {}

---@param source string The source text of the element
---@param startIndex? integer (default: 1) The index of the first character of the element in the source text.
---@param endIndex? integer (default: #source) The index of the last character of the element in the source text.
---@param indentLevel? integer (default: 0) The first character of the line following a line break is indented at this indent size.
---@param value? string (default: source) The content text of the element
---@param kind? PodiumElementKind (default: "text") The kind of the element
---@param extraProps? table (default: {}) The extra properties of the element
---@return PodiumElement
function PodiumElement.new(source, startIndex, endIndex, indentLevel, kind, value, extraProps)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  indentLevel = indentLevel or 0
  kind = kind or "text"
  value = value or source:sub(startIndex, endIndex)
  extraProps = extraProps or {}
  return setmetatable({
    source = source,
    startIndex = startIndex,
    endIndex = endIndex,
    indentLevel = indentLevel,
    kind = kind,
    value = value,
  }, { __index = extraProps })
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

---@param element PodiumElement
---@return PodiumElement
local function trimBlank(element)
  local i = element.startIndex
  while i <= element.endIndex do
    if element.source:sub(i, i):match("%s") then
      i = i + 1
    else
      break
    end
  end
  local j = element.endIndex
  while j >= i do
    if element.source:sub(j, j):match("%s") then
      j = j - 1
    else
      break
    end
  end
  return PodiumElement.new(element.source, i, j, element.indentLevel)
end

---@param element PodiumElement
---@return string[]
local function splitLines(element)
  ---@type string[]
  local lines = {}
  local i = element.startIndex
  while i <= element.endIndex do
    local j = element.source:sub(1, element.endIndex):find("[\r\n]", i)
    if j == nil then
      table.insert(lines, element.source:sub(i, element.endIndex))
      i = element.endIndex + 1
    else
      if element.source:sub(j, j) == "\r" then
        if element.source:sub(j + 1, j + 1) == "\n" then
          j = j + 1
        end
      end
      table.insert(lines, element.source:sub(i, j))
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
  local lines = splitLines(PodiumElement.new(source, 1, #source, 0))
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

---@type PodiumBackendElement
local function splitParagraphs(element)
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
  local startIndex = element.startIndex
  for _, line in ipairs(splitLines(element)) do
    if state_list > 0 then
      table.insert(lines, line)
      if line:match("^=over") then
        state_list = state_list + 1
      elseif line:match("^=back") then
        state_list = state_list - 1
      elseif state_list == 1 and line:match("^%s+$") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "list",
            table.concat(lines)
          )
        )
        startIndex = endIndex + 1
        state_list = 0
        lines = {}
      end
    elseif state_para > 0 then
      table.insert(lines, line)
      if state_para == 1 and line:match("^%s+$") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "para",
            table.concat(lines)
          )
        )
        startIndex = endIndex + 1
        state_para = 0
        lines = {}
      end
    elseif state_verb > 0 then
      if state_verb == 1 and line:match("^%S") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "verb",
            table.concat(lines)
          )
        )
        startIndex = endIndex + 1
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
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            block_name,
            table.concat(lines)
          )
        )
        startIndex = endIndex + 1
        lines = {}
        state_block = 0
      end
    elseif state_cmd > 0 then
      table.insert(lines, line)
      if state_cmd == 1 and line:match("^%s+$") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            cmd_name,
            table.concat(lines)
          )
        )
        startIndex = endIndex + 1
        lines = {}
        state_cmd = 0
      end
    else
      if line:match("^%s+$") then
        local endIndex = startIndex + #line - 1
        table.insert(
          paragraphs,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "skip",
            line
          )
        )
        startIndex = endIndex + 1
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
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          "list",
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    elseif state_para > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          "para",
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    elseif state_verb > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          "verb",
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    elseif state_block > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          block_name,
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    elseif state_cmd > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          cmd_name,
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    end
  end
  return paragraphs
end

---@type PodiumBackendElement
local function splitItem(element)
  local itemState = 0
  ---@type string[]
  local lines = {}
  ---@type PodiumElement[]
  local parts = {}
  local startIndex = element.startIndex
  for _, line in ipairs(splitLines(element)) do
    if itemState == 0 then
      if line:match("^=over") then
        local endIndex = startIndex + #table.concat(lines) - 1
        table.insert(
          parts,
          PodiumElement.new(
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "itempart",
            table.concat(lines)
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
            element.source,
            startIndex,
            endIndex,
            element.indentLevel,
            "list",
            table.concat(lines)
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
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          "list",
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    else
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        parts,
        PodiumElement.new(
          element.source,
          startIndex,
          endIndex,
          element.indentLevel,
          "itempart",
          table.concat(lines)
        )
      )
      startIndex = endIndex + 1
    end
  end
  return parts
end

---@type PodiumBackendElement
local function splitItems(element)
  ---@type PodiumElement[]
  local items = {}
  ---@type "nonitems"|"items"
  local itemsState = "nonitems"
  local allLines = splitLines(element)
  ---@type string[]
  local lines = {}
  local depth = 0
  local index = 1
  local startIndex = element.startIndex
  while index <= #allLines do
    local line = allLines[index]
    if itemsState == "nonitems" then
      if line:match("^=item") then
        if depth == 0 then
          if #lines > 0 then
            local row, col = indexToRowCol(element.source, element.startIndex)
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
              element.source,
              startIndex,
              endIndex,
              element.indentLevel,
              "item",
              table.concat(lines)
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
        element.source,
        startIndex,
        endIndex,
        element.indentLevel,
        "item",
        table.concat(lines)
      )
    )
    startIndex = endIndex + 1
  else
    return splitParagraphs(element)
  end
  return items
end

---@type PodiumBackendElement
local function splitTokens(element)
  ---@type PodiumElement[]
  local tokens = {}
  local i = element.startIndex
  while i <= element.endIndex do
    local ok, b_cmd, _, _, e_cmd =
      pcall(findInline, element.source, i, element.endIndex)
    if ok then
      table.insert(
        tokens,
        PodiumElement.new(
          element.source,
          i,
          b_cmd - 1,
          element.indentLevel,
          "text",
          element.source:sub(i, b_cmd - 1)
        )
      )
      table.insert(
        tokens,
        PodiumElement.new(
          element.source,
          b_cmd,
          e_cmd,
          element.indentLevel,
          element.source:sub(b_cmd, b_cmd),
          element.source:sub(b_cmd, e_cmd)
        )
      )
      i = e_cmd + 1
    else
      table.insert(
        tokens,
        PodiumElement.new(
          element.source,
          i,
          element.endIndex,
          element.indentLevel,
          "text",
          element.source:sub(i, element.endIndex)
        )
      )
      i = element.endIndex + 1
    end
  end
  return tokens
end

---@type PodiumBackendElement
local function splitList(element)
  ---@type 'over' | 'items' | 'back'
  local listState = "over"
  local lines = splitLines(element)
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
  local over_endIndex = element.startIndex
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
      element.source,
      element.startIndex,
      over_endIndex,
      (element.indentLevel + indentLevel),
      "text",
      guessNewline(element.source)
    ),
    PodiumElement.new(
      element.source,
      element.startIndex,
      over_endIndex,
      (element.indentLevel + indentLevel),
      "over",
      table.concat(over_lines),
      { listStyle = list_type }
    ),
    PodiumElement.new(
      element.source,
      items_startIndex,
      items_endIndex,
      (element.indentLevel + indentLevel),
      "items",
      table.concat(items_lines)
    ),
    PodiumElement.new(
      element.source,
      back_startIndex,
      back_endIndex,
      (element.indentLevel + indentLevel),
      "back",
      table.concat(back_lines),
      { listStyle = list_type }
    ),
    PodiumElement.new(
      element.source,
      back_endIndex + 1,
      element.endIndex,
      element.indentLevel,
      "text",
      guessNewline(element.source)
    )
  }
end

---@class PodiumProcessor
---@field backend PodiumBackend
---@field process fun(self: PodiumProcessor, source:string): string
local PodiumProcessor = {}

---@param backend PodiumBackend
---@return PodiumProcessor
function PodiumProcessor.new(backend)
  return {
    backend = backend,
    process = function(self, source)
      local elements = splitParagraphs(PodiumElement.new(source, 1, #source, 0))
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
            if not element.source then
              error("element.source is nil")
            end
            elements = append(
              slice(elements, 1, i - 1),
              self.backend[element.kind](element),
              slice(elements, i + 1)
            )
          end
        else
          elements = append(slice(elements, 1, i - 1), {
            PodiumElement.new(
              source,
              element.startIndex,
              element.endIndex,
              0,
              "skip",
              source:sub(element.startIndex, element.endIndex)
            ),
          }, slice(elements, i + 1))
          i = i + 1
        end
        if element.kind == "cut" then
          shouldProcess = false
        end
      end
      elements = append(
        self.backend["preamble"](PodiumElement.new(source, 1, #source, 0)),
        elements,
        self.backend["postamble"](PodiumElement.new(source, 1, #source, 0))
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
  }
end

---@alias PodiumBackendElement fun(element: PodiumElement): PodiumElement[]
---@alias PodiumBackend table<PodiumElementKind, PodiumBackendElement>

---@param tbl PodiumBackend
---@return PodiumBackend
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
---@param source string
---@return PodiumElement
local function parsed_token(value, indentLevel, source)
  return PodiumElement.new(source, -1, -1, indentLevel, "text", value)
end

local html = rules({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<h1>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</h1>" .. nl, element.indentLevel, element.source) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<h2>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</h2>" .. nl, element.indentLevel, element.source) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<h3>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</h3>" .. nl, element.indentLevel, element.source) }
    )
  end,
  head4 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<h4>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</h4>" .. nl, element.indentLevel, element.source) }
    )
  end,
  para = function(element)
    local nl = guessNewline(element.source)
    element = trimBlank(element)
    return append(
      { parsed_token("<p>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</p>" .. nl, element.indentLevel, element.source) }
    )
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.listStyle == "ordered" then
      return { parsed_token("<ol>" .. nl, element.indentLevel, element.source) }
    else
      return { parsed_token("<ul>" .. nl, element.indentLevel, element.source) }
    end
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    if element.listStyle == "ordered" then
      return { parsed_token("</ol>" .. nl, element.indentLevel, element.source) }
    else
      return { parsed_token("</ul>" .. nl, element.indentLevel, element.source) }
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verb = function(element)
    local nl = guessNewline(element.source)
    return {
      parsed_token("<pre><code>" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("</code></pre>" .. nl, element.indentLevel, element.source),
    }
  end,
  html = function(element)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(element)) do
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
    return { parsed_token(table.concat(lines), element.indentLevel, element.source) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    _, element.startIndex = element.source
      :sub(1, element.endIndex)
      :find("^=item%s*[*0-9]*%.?.", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<li>", element.indentLevel, element.source) },
      splitItem(element),
      { parsed_token("</li>" .. nl, element.indentLevel, element.source) }
    )
  end,
  ["for"] = function(element)
    local nl = guessNewline(element.source)
    _, element.startIndex =
      element.source:sub(1, element.endIndex):find("=for%s+%S+%s", element.startIndex)
    return {
      parsed_token("<pre><code>" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("</code></pre>" .. nl, element.indentLevel, element.source),
    }
  end,
  list = function(element)
    return splitList(element)
  end,
  items = function(element)
    return splitItems(element)
  end,
  itempart = function(element)
    return splitTokens(element)
  end,
  I = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<em>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</em>", element.indentLevel, element.source) }
    )
  end,
  B = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<strong>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</strong>", element.indentLevel, element.source) }
    )
  end,
  C = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("<code>", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("</code>", element.indentLevel, element.source) }
    )
  end,
  L = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    local b, e =
      element.source:sub(1, element.endIndex):find("[^|]*|", element.startIndex)
    if b then
      return append(
        { parsed_token('<a href="', element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, e + 1, element.endIndex, element.indentLevel)),
        { parsed_token('">', element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, b, e - 1, element.indentLevel)),
        { parsed_token("</a>", element.indentLevel, element.source) }
      )
    else
      return append(
        { parsed_token('<a href="', element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token('">', element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token("</a>", element.indentLevel, element.source) }
      )
    end
  end,
  E = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    local arg = element.source:sub(element.startIndex, element.endIndex)
    return { parsed_token("&" .. arg .. ";", element.indentLevel, element.source) }
  end,
  X = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token('<a name="', element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token('"></a>', element.indentLevel, element.source) }
    )
  end,
  Z = function(element)
    return {}
  end,
})

local markdown = rules({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("# ", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token(nl .. nl, element.indentLevel, element.source) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("## ", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token(nl .. nl, element.indentLevel, element.source) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("### ", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token(nl .. nl, element.indentLevel, element.source) }
    )
  end,
  head4 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("#### ", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token(nl .. nl, element.indentLevel, element.source) }
    )
  end,
  para = function(element)
    local nl = guessNewline(element.source)
    element = trimBlank(element)
    return append(splitTokens(element), { parsed_token(nl .. nl, element.indentLevel, element.source) })
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    return {}
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    return {}
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verb = function(element)
    local nl = guessNewline(element.source)
    return {
      parsed_token("```" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("```" .. nl .. nl, element.indentLevel, element.source),
    }
  end,
  html = function(element)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(element)) do
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
    return { parsed_token(table.concat(lines), element.indentLevel, element.source) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local bullet = "-"
    if element.source:sub(1, element.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = element.source
        :sub(1, element.endIndex)
        :find("^=item%s*([0-9]+%.?)", element.startIndex)
    end
    _, element.startIndex = element.source
      :sub(1, element.endIndex)
      :find("^=item%s*[*0-9]*%.?.", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token(bullet .. " ", element.indentLevel, element.source) },
      splitItem(element),
      { parsed_token(nl, element.indentLevel, element.source) }
    )
  end,
  ["for"] = function(element)
    _, element.startIndex =
      element.source:sub(1, element.endIndex):find("=for%s+%S+%s", element.startIndex)
    local nl = guessNewline(element.source)
    return {
      parsed_token("```" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("```" .. nl, element.indentLevel, element.source),
    }
  end,
  list = function(element)
    return splitList(element)
  end,
  items = function(element)
    return splitItems(element)
  end,
  itempart = function(element)
    return splitTokens(element)
  end,
  I = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("*", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("*", element.indentLevel, element.source) }
    )
  end,
  B = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("**", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("**", element.indentLevel, element.source) }
    )
  end,
  C = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("`", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("`", element.indentLevel, element.source) }
    )
  end,
  L = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    local b, e =
      element.source:sub(1, element.endIndex):find("[^|]*|", element.startIndex)
    if b then
      return append(
        { parsed_token("[", element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, b, e - 1, element.endIndex)),
        { parsed_token("](", element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, e + 1, element.endIndex, element.endIndex)),
        { parsed_token(")", element.indentLevel, element.source) }
      )
    else
      return append(
        { parsed_token("[", element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token("](", element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token(")", element.indentLevel, element.source) }
      )
    end
  end,
  E = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    if element.source:sub(element.startIndex, element.endIndex) == "lt" then
      return { parsed_token("<", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "gt" then
      return { parsed_token(">", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "verbar" then
      return { parsed_token("|", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "sol" then
      return { parsed_token("/", element.indentLevel, element.source) }
    else
      return {
        parsed_token(
          "&" .. element.source:sub(element.startIndex, element.endIndex) .. ";",
          element.indentLevel,
          element.source
        ),
      }
    end
  end,
  Z = function(element)
    return {}
  end,
})

---@type PodiumBackendElement
local function vimdoc_head(element)
  local nl = guessNewline(element.source)
  element.startIndex =
    element.source:sub(1, element.endIndex):find("%s", element.startIndex)
  element = trimBlank(element)
  local tokens = splitTokens(element)
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
      { parsed_token("~" .. nl .. string.rep(" ", padding), element.indentLevel, element.source) },
      tags,
      { parsed_token(nl .. nl, element.indentLevel, element.source) }
    )
  else
    return append(tokens, { parsed_token("~" .. nl .. nl, element.indentLevel, element.source) })
  end
end

local vimdoc = rules({
  preamble = function(element)
    local nl = guessNewline(element.source)
    local frontmatter = parseFrontMatter(element.source)
    local filename = frontmatter.name .. ".txt"
    local description = frontmatter.description
    local spaces = string.rep(" ", 78 - #filename - #description - #nl)
    return { parsed_token(filename .. spaces .. description .. nl, element.indentLevel, element.source) }
  end,
  postamble = function(element)
    local nl = guessNewline(element.source)
    return { parsed_token(nl .. "vim:tw=78:ts=8:noet:ft=help:norl:" .. nl, element.indentLevel, element.source) }
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { parsed_token(string.rep("=", 78 - #nl) .. nl, element.indentLevel, element.source) },
      vimdoc_head(element)
    )
  end,
  head2 = vimdoc_head,
  head3 = vimdoc_head,
  head4 = vimdoc_head,
  para = function(element)
    local nl = guessNewline(element.source)
    element = trimBlank(element)
    local tokens = splitTokens(element)
    return append(tokens, { parsed_token(nl .. nl, element.indentLevel, element.source) })
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    return {}
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    return {}
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verb = function(element)
    local nl = guessNewline(element.source)
    return {
      parsed_token(">" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("<" .. nl .. nl, element.indentLevel, element.source),
    }
  end,
  vimdoc = function(element)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(element)) do
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
    return { parsed_token(table.concat(lines), element.indentLevel, element.source) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local bullet = "-"
    if element.source:sub(1, element.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = element.source
        :sub(1, element.endIndex)
        :find("^=item%s*([0-9]+%.?)", element.startIndex)
    end
    _, element.startIndex = element.source
      :sub(1, element.endIndex)
      :find("^=item%s*[*0-9]*%.?.", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token(bullet .. " ", element.indentLevel, element.source) },
      splitItem(element),
      { parsed_token(nl, element.indentLevel, element.source) }
    )
  end,
  ["for"] = function(element)
    _, element.startIndex =
      element.source:sub(1, element.endIndex):find("=for%s+%S+%s", element.startIndex)
    local nl = guessNewline(element.source)
    return {
      parsed_token("<" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token(">" .. nl .. nl, element.indentLevel, element.source),
    }
  end,
  list = function(element)
    return splitList(element)
  end,
  items = function(element)
    return splitItems(element)
  end,
  itempart = function(element)
    return splitTokens(element)
  end,
  C = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("`", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("`", element.indentLevel, element.source) }
    )
  end,
  O = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("'", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("'", element.indentLevel, element.source) }
    )
  end,
  L = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    local b, e =
      element.source:sub(1, element.endIndex):find("[^|]*|", element.startIndex)
    if b then
      return append(
        splitTokens(PodiumElement.new(element.source, b, e - 1, element.startIndex)),
        { parsed_token(" |", element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, e + 1, element.endIndex, e + 1)),
        { parsed_token("|", element.indentLevel, element.source) }
      )
    else
      return append(
        { parsed_token("|", element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token("|", element.indentLevel, element.source) }
      )
    end
  end,
  X = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("*", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("*", element.indentLevel, element.source) }
    )
  end,
  E = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    if element.source:sub(element.startIndex, element.endIndex) == "lt" then
      return { parsed_token("<", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "gt" then
      return { parsed_token(">", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "verbar" then
      return { parsed_token("|", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "sol" then
      return { parsed_token("/", element.indentLevel, element.source) }
    else
      return {
        parsed_token(
          "&" .. element.source:sub(element.startIndex, element.endIndex) .. ";",
          element.indentLevel,
          element.source
        ),
      }
    end
  end,
  Z = function(element)
    return {}
  end,
})

local latex = rules({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\section{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}" .. nl, element.indentLevel, element.source) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\subsection{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}" .. nl, element.indentLevel, element.source) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    element.startIndex =
      element.source:sub(1, element.endIndex):find("%s", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\subsubsection{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}" .. nl, element.indentLevel, element.source) }
    )
  end,
  para = function(element)
    local nl = guessNewline(element.source)
    element = trimBlank(element)
    return append(splitTokens(element), { parsed_token(nl, element.indentLevel, element.source) })
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.listStyle == "ordered" then
      return { parsed_token("\\begin{enumerate}" .. nl, element.indentLevel, element.source) }
    else
      return { parsed_token("\\begin{itemize}" .. nl, element.indentLevel, element.source) }
    end
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    if element.listStyle == "ordered" then
      return { parsed_token("\\end{enumerate}" .. nl, element.indentLevel, element.source) }
    else
      return { parsed_token("\\end{itemize}" .. nl, element.indentLevel, element.source) }
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verb = function(element)
    local nl = guessNewline(element.source)
    return {
      parsed_token("\\begin{verbatim}" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("\\end{verbatim}" .. nl, element.indentLevel, element.source),
    }
  end,
  latex = function(element)
    ---@type string[]
    local lines = {}
    local blockState = 0
    for _, line in ipairs(splitLines(element)) do
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
    return { parsed_token(table.concat(lines), element.indentLevel, element.source) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    _, element.startIndex = element.source
      :sub(1, element.endIndex)
      :find("^=item%s*[*0-9]*%.?.", element.startIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\item ", element.indentLevel, element.source) },
      splitItem(element),
      { parsed_token(nl, element.indentLevel, element.source) }
    )
  end,
  ["for"] = function(element)
    local nl = guessNewline(element.source)
    _, element.startIndex =
      element.source:sub(1, element.endIndex):find("=for%s+%S+%s", element.startIndex)
    return {
      parsed_token("\\begin{verbatim}" .. nl, element.indentLevel, element.source),
      parsed_token(element.source:sub(element.startIndex, element.endIndex), element.indentLevel, element.source),
      parsed_token("\\end{verbatim}" .. nl, element.indentLevel, element.source),
    }
  end,
  list = function(element)
    return splitList(element)
  end,
  items = function(element)
    return splitItems(element)
  end,
  itempart = function(element)
    return splitTokens(element)
  end,
  I = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\textit{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}", element.indentLevel, element.source) }
    )
  end,
  B = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\textbf{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}", element.indentLevel, element.source) }
    )
  end,
  C = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\verb|", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("|", element.indentLevel, element.source) }
    )
  end,
  L = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    local b, e =
      element.source:sub(1, element.endIndex):find("[^|]*|", element.startIndex)
    if b then
      return append(
        { parsed_token("\\href{", element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, e + 1, element.endIndex, element.indentLevel)),
        { parsed_token("}{", element.indentLevel, element.source) },
        splitTokens(PodiumElement.new(element.source, b, e - 1, element.indentLevel)),
        { parsed_token("}", element.indentLevel, element.source) }
      )
    elseif
      element.source:sub(element.startIndex, element.endIndex):match("^https?://")
    then
      return append(
        { parsed_token("\\url{", element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token("}", element.indentLevel, element.source) }
      )
    else
      return {
        { parsed_token("\\ref{", element.indentLevel, element.source) },
        splitTokens(element),
        { parsed_token("}", element.indentLevel, element.source) },
      }
    end
  end,
  E = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    if element.source:sub(element.startIndex, element.endIndex) == "lt" then
      return { parsed_token("<", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "gt" then
      return { parsed_token(">", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "verbar" then
      return { parsed_token("|", element.indentLevel, element.source) }
    elseif element.source:sub(element.startIndex, element.endIndex) == "sol" then
      return { parsed_token("/", element.indentLevel, element.source) }
    else
      return {
        parsed_token("\\texttt{", element.indentLevel, element.source),
        splitTokens(element),
        parsed_token("}", element.indentLevel, element.source),
      }
    end
  end,
  X = function(element)
    _, element.startIndex, element.endIndex, _ =
      findInline(element.source, element.startIndex, element.endIndex)
    element = trimBlank(element)
    return append(
      { parsed_token("\\label{", element.indentLevel, element.source) },
      splitTokens(element),
      { parsed_token("}", element.indentLevel, element.source) }
    )
  end,
  Z = function(element)
    return {}
  end,
})

M.PodiumElement = PodiumElement
M.PodiumProcessor = PodiumProcessor
M.findInline = findInline
M.splitLines = splitLines
M.splitParagraphs = splitParagraphs
M.splitItem = splitItem
M.splitItems = splitItems
M.findInline = findInline
M.splitTokens = splitTokens
M.splitList = splitList
M.html = html
M.markdown = markdown
M.latex = latex
M.vimdoc = vimdoc

if arg then
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
   local processor = PodiumProcessor.new(M[arg[1]])
   local output = processor:process(input)
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
end

return M
