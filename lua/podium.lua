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
---| 'verbatim'
---| 'for'
---| 'head1'
---| 'head2'
---| 'head3'
---| 'head4'
---@alias PodiumElementKindInternalConstituent -- All internal constituents
---| 'backspace'
---| 'list'
---| 'items'
---| 'itempart'
---| 'paragraph'
---| 'text'
---| 'preamble'
---| 'postamble'
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
---@field extraProps table The extra properties of the element
---@field clone fun(self: PodiumElement, props?: table): PodiumElement
local PodiumElement = {}

---@param self PodiumElement
---@param props? table
---@return PodiumElement
function PodiumElement.clone(self, props)
  props = props or {}
  return setmetatable({
    source = props.source or self.source,
    startIndex = props.startIndex or self.startIndex,
    endIndex = props.endIndex or self.endIndex,
    indentLevel = props.indentLevel or self.indentLevel,
    kind = props.kind or self.kind,
    value = props.value or self.value,
    extraProps = props.extraProps or self.extraProps,
  }, { __index = PodiumElement })
end

---@param source string The source text of the element
---@param startIndex? integer (default: 1) The index of the first character of the element in the source text.
---@param endIndex? integer (default: #source) The index of the last character of the element in the source text.
---@param indentLevel? integer (default: 0) The first character of the line following a line break is indented at this indent size.
---@param value? string (default: source) The content text of the element
---@param kind? PodiumElementKind (default: "text") The kind of the element
---@param extraProps? table (default: {}) The extra properties of the element
---@return PodiumElement
function PodiumElement.new(
  source,
  startIndex,
  endIndex,
  indentLevel,
  kind,
  value,
  extraProps
)
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
    extraProps = extraProps,
  }, { __index = PodiumElement })
end

---@param self PodiumElement
---@param pattern string
---@param startIndex? integer
---@param endIndex? integer
---@param plain? boolean
---@return integer, integer, ...any
function PodiumElement.find(self, pattern, startIndex, endIndex, plain)
  startIndex = startIndex or self.startIndex
  endIndex = endIndex or self.endIndex
  plain = plain or false
  return self.source:sub(1, endIndex):find(pattern, startIndex, plain)
end

---@param self PodiumElement
---@param startIndex? integer
---@param endIndex? integer
function PodiumElement.sub(self, startIndex, endIndex)
  startIndex = startIndex or self.startIndex
  endIndex = endIndex or self.endIndex
  return self:clone({
    startIndex = startIndex,
    endIndex = endIndex,
    value = self.source:sub(startIndex, endIndex),
  })
end

---@param self PodiumElement
---@return PodiumElement
function PodiumElement.trim(self)
  local startIndex, _, space = self:find("%S.*%S(%s*)")
  startIndex, space = startIndex or self.startIndex, space or ""
  return self:sub(startIndex, self.endIndex - #space)
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
---@return string[]
local function splitLines(element)
  ---@type string[]
  local lines = {}
  local i = element.startIndex
  while i <= element.endIndex do
    local j = element:find("[\r\n]", i)
    if j == nil then
      table.insert(lines, element:sub(i).value)
      i = element.endIndex + 1
    else
      if element:sub(j, j).value == "\r" then
        if element:sub(j + 1, j + 1).value == "\n" then
          j = j + 1
        end
      end
      table.insert(lines, element:sub(i, j).value)
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

---@param element PodiumElement
---@return integer,integer,integer,integer
local function findFormattingCode(element)
  for b_cmd = element.startIndex, element.endIndex do
    if element.source:sub(b_cmd, b_cmd):match("[A-Z]") then
      if element.source:sub(b_cmd + 1, b_cmd + 1) == "<" then
        local count = 1
        local space = ""
        local i = b_cmd + 2
        local b_arg, e_arg = nil, nil
        while i <= element.endIndex do
          if element.source:sub(i, i) == "<" then
            count = count + 1
            i = i + 1
          elseif element.source:sub(i, i):match("%s") then
            b_arg = i + 1
            space = "%s"
            break
          else
            b_arg = b_cmd + 2
            count = 1
            break
          end
        end
        if i > element.endIndex then
          local row, col = indexToRowCol(element.source, b_cmd)
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
        while i <= element.endIndex do
          if element.source:sub(i, i + #angles - 1):match(angles) then
            e_arg = i - 1
            break
          end
          if element.source:sub(i, i) == "<" then
            if element.source:sub(i - 1, i - 1):match("[A-Z]") then
              _, _, _, i =
                findFormattingCode(element:sub(i - 1, element.endIndex))
            end
          end
          i = i + 1
        end
        if i > element.endIndex then
          local row, col = indexToRowCol(element.source, b_cmd)
          error(
            "Missing closing brackets '"
              .. string.rep(">", count)
              .. "':"
              .. row
              .. ":"
              .. col
              .. ": "
              .. element.source:sub(b_cmd, b_cmd + count)
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
          element:sub(startIndex, endIndex):clone({ kind = "list" })
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
          element:sub(startIndex, endIndex):clone({
            kind = "paragraph",
          })
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
          element:sub(startIndex, endIndex):clone({
            kind = "verbatim",
          })
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
          element:sub(startIndex, endIndex):clone({
            kind = block_name,
          })
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
          element:sub(startIndex, endIndex):clone({
            kind = cmd_name,
          })
        )
        startIndex = endIndex + 1
        lines = {}
        state_cmd = 0
      end
    else
      if line:match("^%s+$") then
        local endIndex = startIndex + #line - 1
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
        element:sub(startIndex, endIndex):clone({
          kind = "list",
        })
      )
      startIndex = endIndex + 1
    elseif state_para > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        element:sub(startIndex, endIndex):clone({
          kind = "paragraph",
        })
      )
      startIndex = endIndex + 1
    elseif state_verb > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        element:sub(startIndex, endIndex):clone({
          kind = "verbatim",
        })
      )
      startIndex = endIndex + 1
    elseif state_block > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        element:sub(startIndex, endIndex):clone({
          kind = block_name,
        })
      )
      startIndex = endIndex + 1
    elseif state_cmd > 0 then
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        paragraphs,
        element:sub(startIndex, endIndex):clone({
          kind = cmd_name,
        })
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
          element:sub(startIndex, endIndex):trim():clone({ kind = "itempart" })
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
          element:sub(startIndex, endIndex):trim():clone({ kind = "list" })
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
        element:sub(startIndex, endIndex):trim():clone({ kind = "list" })
      )
      startIndex = endIndex + 1
    else
      local endIndex = startIndex + #table.concat(lines) - 1
      table.insert(
        parts,
        element:sub(startIndex, endIndex):trim():clone({ kind = "itempart" })
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
            element:sub(startIndex, endIndex):clone({
              kind = "item",
            })
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
      element:sub(startIndex, endIndex):clone({
        kind = "item",
      })
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
    local ok, b_cmd, _, _, e_cmd = pcall(findFormattingCode, element:sub(i))
    if ok then
      table.insert(
        tokens,
        element:sub(i, b_cmd - 1):clone({
          kind = "text",
        })
      )
      table.insert(
        tokens,
        element:sub(b_cmd, e_cmd):clone({
          kind = element.source:sub(b_cmd, b_cmd),
        })
      )
      i = e_cmd + 1
    else
      table.insert(
        tokens,
        element:sub(i):clone({
          kind = "text",
        })
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
    element:clone({
      endIndex = over_endIndex,
      kind = "over",
      value = table.concat(over_lines),
      indentLevel = (element.indentLevel + indentLevel),
      extraProps = {
        listStyle = list_type,
        listDepth = (element.extraProps.listDepth or 0) + 1,
      },
    }),
    element:clone({
      startIndex = items_startIndex,
      endIndex = items_endIndex,
      kind = "items",
      value = table.concat(items_lines),
      indentLevel = (element.indentLevel + indentLevel),
      extraProps = {
        listDepth = (element.extraProps.listDepth or 0) + 1,
      },
    }),
    element:clone({
      kind = "backspace",
      extraProps = {
        deleteCount = indentLevel,
        listDepth = (element.extraProps.listDepth or 0) + 1,
      },
    }),
    element:clone({
      startIndex = back_startIndex,
      endIndex = back_endIndex,
      kind = "back",
      value = table.concat(back_lines),
      extraProps = {
        listStyle = list_type,
        listDepth = (element.extraProps.listDepth or 0) + 1,
      },
    }),
  }
end

---@param backend PodiumBackend | string
---@param source string
---@return string
local function process(backend, source)
  backend = type(backend) == "string" and M[backend] or backend ---@cast backend PodiumBackend
  local elements = splitParagraphs(PodiumElement.new(source))
  local nl = guessNewline(source)
  local shouldProcess = false
  local i = 1
  while i <= #elements do
    local element = elements[i]
    if element.kind == "pod" then
      shouldProcess = true
    end
    if shouldProcess then
      if element.kind == "text" or element.kind == "backspace" then
        i = i + 1
      else
        if element.source == nil then
          error("element.source is nil")
        end
        if type(element) ~= "table" then
          error("element is not a table")
        end
        elements = append(
          slice(elements, 1, i - 1),
          backend.rules[element.kind](element),
          slice(elements, i + 1)
        )
      end
    else
      elements = append(slice(elements, 1, i - 1), slice(elements, i + 1))
    end
    if element.kind == "cut" then
      shouldProcess = false
    end
  end
  elements = append(
    backend.rules["preamble"](PodiumElement.new(source)),
    elements,
    backend.rules["postamble"](PodiumElement.new(source))
  )
  local output = ""
  for _, element in ipairs(elements) do
    if element.kind == "backspace" then
      local count = element.extraProps.deleteCount or 1
      output = output:sub(1, #output - count)
    else
      local text = element.value:gsub(nl, nl .. (" "):rep(element.indentLevel))
      output = output .. text
    end
  end
  return output
end

---@alias PodiumBackendElement fun(element: PodiumElement): PodiumElement[]
---@class PodiumBackend
---@field rules table<string, PodiumBackendElement>
---@field registerSimpleFormattingCode fun(self: PodiumBackend, name: string, fun: fun(content: string): string): PodiumBackend
---@field registerSimpleCommand fun(self: PodiumBackend, name: string, fun: fun(content: string): string): PodiumBackend
---@field registerSimpleDataParagraph fun(self: PodiumBackend, name: string, fun: fun(content: string): string): PodiumBackend
---@field registerSimple fun(self: PodiumBackend, name: string, fun: fun(content: string): string): PodiumBackend
local PodiumBackend = {
  rules = {},
}

---@param self PodiumBackend
---@param name string
---@param fun fun(content: string): string
function PodiumBackend.registerSimpleFormattingCode(self, name, fun)
  self = type(self) == "string" and M[self] or self ---@cast self PodiumBackend
  self.rules[name] = function(element)
    local _, b_arg, e_arg, _ = findFormattingCode(element)
    local arg = element.source:sub(b_arg, e_arg)
    return {
      element:clone({ kind = "text", value = fun(arg) }),
    }
  end
  return self
end

---@param self PodiumBackend | string
---@param name string
---@param fun fun(content: string): string
---@return PodiumBackend
function PodiumBackend.registerSimpleCommand(self, name, fun)
  self = type(self) == "string" and M[self] or self ---@cast self PodiumBackend
  self.rules[name] = function(element)
    local arg =
      element.source:sub(element.startIndex, element.endIndex):gsub("^=%S+", "")
    return {
      element:clone({ kind = "text", value = fun(arg) }),
    }
  end
  return self
end

---@param element PodiumElement
---@return integer, integer, integer, integer
---The index of the first character of =begin command
---The index of the first character of content
---The index of the last character of content
---The index of the last character of =end command
local function findDataParagraph(element)
  local startIndex = element.startIndex
  local endIndex = element.startIndex
  local lines = {}
  local blockState = 0
  for _, line in ipairs(splitLines(element)) do
    if blockState == 0 then
      startIndex = startIndex + #line
      endIndex = endIndex + #line
      if line:match("^=begin") then
        blockState = 1
      end
    elseif blockState == 1 then
      startIndex = startIndex + #line
      endIndex = endIndex + #line
      if line:match("^%s*$") then
        startIndex = startIndex - #line - 1
        table.insert(lines, line)
        blockState = 2
      end
    elseif blockState == 2 then
      endIndex = endIndex + #line
      if line:match("^%s*$") then
        table.insert(lines, line)
        blockState = 3
      else
        table.insert(lines, line)
      end
    elseif blockState == 3 then
      endIndex = endIndex + #line
      if line:match("^=end") then
        endIndex = endIndex - #line
        blockState = 4
      else
        table.insert(lines, line)
        blockState = 3
      end
    end
  end
  return element.startIndex, startIndex, endIndex - 1, element.endIndex
end

---@param self PodiumBackend
---@param name string
---@param fun fun(content: string): string
---@return PodiumBackend
function PodiumBackend.registerSimpleDataParagraph(self, name, fun)
  self = type(self) == "string" and M[self] or self ---@cast self PodiumBackend
  self.rules[name] = function(element)
    local _, startIndex, endIndex, _ = findDataParagraph(element)
    local arg = element:sub(startIndex, endIndex).value
    return {
      element:clone({ kind = "text", value = fun(arg) }),
    }
  end
  return self
end

---@param self PodiumBackend
---@param name string
---@param fun fun(content: string): string
---@return PodiumBackend
function PodiumBackend.registerSimple(self, name, fun)
  self = type(self) == "string" and M[self] or self ---@cast self PodiumBackend
  self.rules[name] = function(element)
    local startIndex, endIndex = findDataParagraph(element)
    local arg = element.source:sub(startIndex, endIndex)
    return {
      element:clone({ kind = "text", value = fun(arg) }),
    }
  end
  return self
end

---@param rules table<string, PodiumBackendElement>
---@return PodiumBackend
function PodiumBackend.new(rules)
  setmetatable(rules, {
    __index = function(_table, _key)
      return function(_element)
        return {}
      end
    end,
  })
  local self = setmetatable({
    rules = rules,
  }, {
    __index = PodiumBackend,
  })
  return self
end

local html = PodiumBackend.new({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ value = "<h1>", kind = "text" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ value = "</h1>" .. nl, kind = "text" }) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ value = "<h2>", kind = "text" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ value = "</h2>" .. nl, kind = "text" }) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ value = "<h3>", kind = "text" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ value = "</h3>" .. nl, kind = "text" }) }
    )
  end,
  head4 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ value = "<h4>", kind = "text" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ value = "</h4>" .. nl, kind = "text" }) }
    )
  end,
  paragraph = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ value = "<p>", kind = "text" }) },
      splitTokens(element:trim()),
      { element:clone({ value = "</p>" .. nl, kind = "text" }) }
    )
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listStyle == "ordered" then
      return {
        element:clone({ value = "<ol>" .. nl, kind = "text" }),
      }
    else
      return {
        element:clone({ value = "<ul>" .. nl, kind = "text" }),
      }
    end
  end,
  back = function(element)
    local ld = element.extraProps.listDepth
    local nl = guessNewline(element.source)
    if element.extraProps.listStyle == "ordered" then
      return {
        element:clone({ value = "</ol>", kind = "text" }),
        element:clone({ value = (ld == 1 and nl or ""), kind = "text" }),
      }
    else
      return {
        element:clone({ value = "</ul>", kind = "text" }),
        element:clone({ value = (ld == 1 and nl or ""), kind = "text" }),
      }
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verbatim = function(element)
    local nl = guessNewline(element.source)
    return {
      element:clone({ value = "<pre><code>", kind = "text" }),
      element:clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ value = "</code></pre>" .. nl, kind = "text" }),
    }
  end,
  html = function(element)
    if type(element) ~= "table" then
      print(type(element))
      error("element is not a table")
    end
    local _, startIndex, endIndex, _ = findDataParagraph(element)
    return { element:sub(startIndex, endIndex):clone({ kind = "text" }) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local _, startIndex = element:find("^=item%s*[*0-9]*%.?.")
    return append(
      { element:clone({ kind = "text", value = "<li>" }) },
      splitItem(element:sub(startIndex):trim()),
      { element:clone({ kind = "text", value = "</li>" .. nl }) }
    )
  end,
  ["for"] = function(element)
    local nl = guessNewline(element.source)
    local _, startIndex = element:find("^=for%s+%S+%s")
    return {
      element:clone({ kind = "text", value = "<pre><code>" .. nl }),
      element:sub(startIndex):trim():clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "</code></pre>" .. nl }),
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
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "<em>", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "</em>", kind = "text" }) }
    )
  end,
  B = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "<strong>", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "</strong>", kind = "text" }) }
    )
  end,
  C = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "<code>", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "</code>", kind = "text" }) }
    )
  end,
  L = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local newElement = element:sub(startIndex, endIndex)
    local b, e = newElement:find("[^|]*|")
    if b then
      return append(
        { element:clone({ value = '<a href="', kind = "text" }) },
        splitTokens(newElement:sub(e + 1)),
        { element:clone({ value = '">', kind = "text" }) },
        splitTokens(newElement:sub(b, e - 1)),
        { element:clone({ value = "</a>", kind = "text" }) }
      )
    else
      return append(
        { element:clone({ value = '<a href="', kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = '">', kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = "</a>", kind = "text" }) }
      )
    end
  end,
  E = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local value = element:sub(startIndex, endIndex):trim().value
    return {
      element:clone({ value = "&" .. value .. ";", kind = "text" }),
    }
  end,
  X = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = '<a name=">', kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = '">', kind = "text" }) },
      { element:clone({ value = "</a>", kind = "text" }) }
    )
  end,
  Z = function(element)
    return {}
  end,
})

local markdown = PodiumBackend.new({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "# " }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = nl .. nl }) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "## " }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = nl .. nl }) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "### " }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = nl .. nl }) }
    )
  end,
  head4 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "#### " }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = nl .. nl }) }
    )
  end,
  paragraph = function(element)
    local nl = guessNewline(element.source)
    return append(
      splitTokens(element:trim()),
      { element:clone({ kind = "text", value = nl .. nl }) }
    )
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listDepth == 1 then
      return {
        element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
        element:clone({ kind = "text", value = nl }),
      }
    else
      return {
        element:clone({ kind = "text", value = nl }),
      }
    end
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listDepth == 1 then
      return { element:clone({ kind = "text", value = nl }) }
    else
      return {}
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verbatim = function(element)
    local nl = guessNewline(element.source)
    return {
      element:clone({ kind = "text", value = "```" .. nl }),
      element:clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "```" .. nl .. nl }),
    }
  end,
  html = function(element)
    local _, startIndex, endIndex, _ = findDataParagraph(element)
    return {
      element:sub(startIndex, endIndex):clone({ kind = "text" }),
    }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local bullet = "-"
    if element.source:sub(1, element.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = element:find("^=item%s*([0-9]+%.?)")
    end
    local _, startIndex = element:find("^=item%s*[*0-9]*%.?.")
    return append(
      { element:clone({ kind = "text", value = bullet .. " " }) },
      splitItem(element:sub(startIndex):trim()),
      { element:clone({ kind = "text", value = nl }) }
    )
  end,
  ["for"] = function(element)
    local nl = guessNewline(element.source)
    local _, startIndex = element:find("=for%s+%S+%s")
    return {
      element:clone({ kind = "text", value = "```" .. nl }),
      element:sub(startIndex):trim():clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "```" .. nl }),
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
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "*", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "*", kind = "text" }) }
    )
  end,
  B = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "**", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "**", kind = "text" }) }
    )
  end,
  C = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "`", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "`", kind = "text" }) }
    )
  end,
  L = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local newElement = element:sub(startIndex, endIndex):trim()
    local b, e = newElement:find("[^|]*|")
    if b then
      return append(
        { element:clone({ value = "[", kind = "text" }) },
        splitTokens(newElement:sub(b, e - 1)),
        { element:clone({ value = "](", kind = "text" }) },
        splitTokens(newElement:sub(e + 1)),
        { element:clone({ value = ")", kind = "text" }) }
      )
    else
      return append(
        { element:clone({ value = "[", kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = "](", kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = ")", kind = "text" }) }
      )
    end
  end,
  E = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local value = element:sub(startIndex, endIndex):trim().value
    if value == "lt" then
      return { element:clone({ value = "<", kind = "text" }) }
    elseif value == "gt" then
      return { element:clone({ value = ">", kind = "text" }) }
    elseif value == "verbar" then
      return { element:clone({ value = "|", kind = "text" }) }
    elseif value == "sol" then
      return { element:clone({ value = "/", kind = "text" }) }
    else
      return {
        element:clone({
          value = "&" .. value .. ";",
          kind = "text",
        }),
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
  local tokens = splitTokens(element:sub((element:find("%s"))):trim())
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
    return append(tokens, {
      element:clone({
        kind = "text",
        value = "~" .. nl,
        string.rep(" ", padding),
      }),
    }, tags, { element:clone({ kind = "text", value = nl .. nl }) })
  else
    return append(
      tokens,
      { element:clone({ kind = "text", value = "~" .. nl .. nl }) }
    )
  end
end

local vimdoc = PodiumBackend.new({
  preamble = function(element)
    local nl = guessNewline(element.source)
    local frontmatter = parseFrontMatter(element.source)
    local filename = "*" .. (frontmatter.name or "untitled") .. ".txt*"
    local description = frontmatter.description or "No description"
    local spaces = string.rep(" ", 78 - #filename - #description - #nl)
    return {
      element:clone({
        kind = "text",
        value = filename .. spaces .. description .. nl,
      }),
    }
  end,
  postamble = function(element)
    local nl = guessNewline(element.source)
    return {
      element:clone({
        kind = "text",
        value = nl .. "vim:tw=78:ts=8:noet:ft=help:norl:" .. nl,
      }),
    }
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    return append({
      element:clone({
        kind = "text",
        value = string.rep("=", 78 - #nl) .. nl,
      }),
    }, vimdoc_head(element))
  end,
  head2 = vimdoc_head,
  head3 = vimdoc_head,
  head4 = vimdoc_head,
  paragraph = function(element)
    local nl = guessNewline(element.source)
    return append(splitTokens(element:trim()), {
      element:clone({ kind = "text", value = nl .. nl }),
    })
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listDepth == 1 then
      return {
        element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
        element:clone({ kind = "text", value = nl }),
      }
    else
      return {
        element:clone({ kind = "text", value = nl }),
      }
    end
  end,
  back = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listDepth == 1 then
      return { element:clone({ kind = "text", value = nl }) }
    else
      return {}
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verbatim = function(element)
    local nl = guessNewline(element.source)
    return {
      element:clone({ kind = "text", value = ">" .. nl }),
      element:clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "<" .. nl .. nl }),
    }
  end,
  vimdoc = function(element)
    local _, startIndex, endIndex, _ = findDataParagraph(element)
    return { element:sub(startIndex, endIndex) }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local bullet = "-"
    if element.source:sub(1, element.endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = element:find("^=item%s*([0-9]+%.?)")
    end
    local _, startIndex = element:find("^=item%s*[*0-9]*%.?.")
    return append(
      { element:clone({ kind = "text", value = bullet .. " " }) },
      splitItem(element:sub(startIndex):trim()),
      { element:clone({ kind = "text", value = nl }) }
    )
  end,
  ["for"] = function(element)
    local _, startIndex = element:find("^=for%s+%S+%s")
    local nl = guessNewline(element.source)
    return {
      element:clone({ kind = "text", value = ">" .. nl }),
      element:sub(startIndex):trim():clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "<" .. nl .. nl }),
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
  B = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ kind = "text", value = "{" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ kind = "text", value = "}" }) }
    )
  end,
  C = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ kind = "text", value = "`" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ kind = "text", value = "`" }) }
    )
  end,
  O = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ kind = "text", value = "'" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ kind = "text", value = "'" }) }
    )
  end,
  L = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local newElement = element:sub(startIndex, endIndex):trim()
    local b, e = newElement:find("[^|]*|")
    if b then
      return append(
        splitTokens(newElement:sub(b, e - 1)),
        { element:clone({ kind = "text", value = " |" }) },
        splitTokens(newElement:sub(e + 1)),
        { element:clone({ kind = "text", value = "|" }) }
      )
    else
      return append(
        { element:clone({ kind = "text", value = "|" }) },
        splitTokens(newElement),
        { element:clone({ kind = "text", value = "|" }) }
      )
    end
  end,
  X = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ kind = "text", value = "*" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ kind = "text", value = "*" }) }
    )
  end,
  E = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local value = element:sub(startIndex, endIndex):trim().value
    if value == "lt" then
      return { element:clone({ kind = "text", value = "<" }) }
    elseif value == "gt" then
      return { element:clone({ kind = "text", value = ">" }) }
    elseif value == "verbar" then
      return { element:clone({ kind = "text", value = "|" }) }
    elseif value == "sol" then
      return { element:clone({ kind = "text", value = "/" }) }
    else
      return {
        element:clone({ kind = "text", value = "&" .. value .. ";" }),
      }
    end
  end,
  Z = function(element)
    return {}
  end,
})

local latex = PodiumBackend.new({
  preamble = function(element)
    return {}
  end,
  postamble = function(element)
    return {}
  end,
  head1 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "\\section{" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = "}" .. nl }) }
    )
  end,
  head2 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "\\subsection{" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = "}" .. nl }) }
    )
  end,
  head3 = function(element)
    local nl = guessNewline(element.source)
    return append(
      { element:clone({ kind = "text", value = "\\subsubsection{" }) },
      splitTokens(element:sub((element:find("%s"))):trim()),
      { element:clone({ kind = "text", value = "}" .. nl }) }
    )
  end,
  paragraph = function(element)
    local nl = guessNewline(element.source)
    return append(
      splitTokens(element:trim()),
      { element:clone({ kind = "text", value = nl }) }
    )
  end,
  over = function(element)
    local nl = guessNewline(element.source)
    if element.extraProps.listStyle == "ordered" then
      return {
        element:clone({ kind = "text", value = "\\begin{enumerate}" .. nl }),
      }
    else
      return {
        element:clone({ kind = "text", value = "\\begin{itemize}" .. nl }),
      }
    end
  end,
  back = function(element)
    local ld = element.extraProps.listDepth
    local nl = guessNewline(element.source)
    if element.extraProps.listStyle == "ordered" then
      return {
        element:clone({ kind = "text", value = "\\end{enumerate}" }),
        element:clone({ kind = "text", value = ld == 1 and nl or "" }),
      }
    else
      return {
        element:clone({ kind = "text", value = "\\end{itemize}" }),
        element:clone({ kind = "text", value = ld == 1 and nl or "" }),
      }
    end
  end,
  cut = function(element)
    return {}
  end,
  pod = function(element)
    return {}
  end,
  verbatim = function(element)
    local nl = guessNewline(element.source)
    return {
      element:clone({ kind = "text", value = "\\begin{verbatim}" .. nl }),
      element:clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "\\end{verbatim}" .. nl }),
    }
  end,
  latex = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return {
      element:sub(startIndex, endIndex):clone({ kind = "text" }),
    }
  end,
  item = function(element)
    local nl = guessNewline(element.source)
    local _, startIndex = element:find("^=item%s*[*0-9]*%.?.")
    return append(
      { element:clone({ kind = "text", value = "\\item " }) },
      splitItem(element:sub(startIndex):trim()),
      { element:clone({ kind = "text", value = nl }) }
    )
  end,
  ["for"] = function(element)
    local nl = guessNewline(element.source)
    local _, startIndex = element:find("^=for%s+%S+%s")
    return {
      element:clone({ kind = "text", value = "\\begin{verbatim}" .. nl }),
      element:sub(startIndex):trim():clone({ kind = "text" }),
      element:clone({ kind = "backspace", extraProps = { deleteCount = 1 } }),
      element:clone({ kind = "text", value = "\\end{verbatim}" .. nl }),
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
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "\\textit{", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "}", kind = "text" }) }
    )
  end,
  B = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "\\textbf{", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "}", kind = "text" }) }
    )
  end,
  C = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "\\verb|", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "|", kind = "text" }) }
    )
  end,
  L = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local newElement = element:sub(startIndex, endIndex):trim()
    local b, e = newElement:find("[^|]*|")
    if b then
      return append(
        { element:clone({ value = "\\href{", kind = "text" }) },
        splitTokens(newElement:sub(e + 1)),
        { element:clone({ value = "}{", kind = "text" }) },
        splitTokens(newElement:sub(b, e - 1)),
        { element:clone({ value = "}", kind = "text" }) }
      )
    elseif element.value:match("^https?://") then
      return append(
        { element:clone({ value = "\\url{", kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = "}", kind = "text" }) }
      )
    else
      return append(
        { element:clone({ value = "\\ref{", kind = "text" }) },
        splitTokens(newElement),
        { element:clone({ value = "}", kind = "text" }) }
      )
    end
  end,
  E = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    local value = element:sub(startIndex, endIndex):trim().value
    if value == "lt" then
      return { element:clone({ value = "<", kind = "text" }) }
    elseif value == "gt" then
      return { element:clone({ value = ">", kind = "text" }) }
    elseif value == "verbar" then
      return { element:clone({ value = "|", kind = "text" }) }
    elseif value == "sol" then
      return { element:clone({ value = "/", kind = "text" }) }
    else
      return {
        element:clone({ value = "\\texttt{", kind = "text" }),
        element:clone({ value = value }),
        element:clone({ value = "}", kind = "text" }),
      }
    end
  end,
  X = function(element)
    local _, startIndex, endIndex, _ = findFormattingCode(element)
    return append(
      { element:clone({ value = "\\label{", kind = "text" }) },
      splitTokens(element:sub(startIndex, endIndex):trim()),
      { element:clone({ value = "}", kind = "text" }) }
    )
  end,
  Z = function(element)
    return {}
  end,
})

M.PodiumElement = PodiumElement
M.PodiumBackend = PodiumBackend
M.append = append
M.slice = slice
M.guessNewline = guessNewline
M.indexToRowCol = indexToRowCol
M.splitLines = splitLines
M.splitParagraphs = splitParagraphs
M.splitItem = splitItem
M.splitItems = splitItems
M.findFormattingCode = findFormattingCode
M.findDataParagraph = findDataParagraph
M.splitTokens = splitTokens
M.splitList = splitList
M.html = html
M.markdown = markdown
M.latex = latex
M.vimdoc = vimdoc
M.process = process

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
    local output = process(M[arg[1]], input)
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
