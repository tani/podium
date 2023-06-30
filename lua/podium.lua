#!/usr/bin/env lua

local M = {}
local _ -- dummy

---@param t table
---@param indent? number  always 0
-- luacheck: ignore
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

---@param strings string[]
---@param sep? string
---@return string
local function join(strings, sep)
  sep = sep or ""
  local r = ""
  for _, s in ipairs(strings) do
    r = r .. s .. sep
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

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return string,integer,integer
local function trimBlank(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  local i = startIndex
  while i <= endIndex do
    if source:sub(i, i):match("%s") then
      i = i + 1
    else
      break
    end
  end
  local j = endIndex
  while j >= i do
    if source:sub(j, j):match("%s") then
      j = j - 1
    else
      break
    end
  end
  return source:sub(i, j), i, j
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return string[]
local function splitLines(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  ---@type string[]
  local lines = {}
  local i = startIndex
  while i <= endIndex do
    local j = source:sub(1, endIndex):find("[\r\n]", i)
    if j == nil then
      table.insert(lines, source:sub(i, endIndex))
      i = endIndex + 1
    else
      if source:sub(j, j) == "\r" then
        if source:sub(j + 1, j + 1) == "\n" then
          j = j + 1
        end
      end
      table.insert(lines, source:sub(i, j))
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
  local lines = splitLines(source)
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
---@return integer|nil,integer?,integer?,integer?
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
          error("ERROR:" .. row .. ":" .. col .. ": " .. "Missing closing brackets '<" .. string.rep(">", count) .. "'")
        end
        local angles = space .. string.rep(">", count)
        while i <= endIndex do
          if source:sub(i, i + #angles - 1):match(angles) then
            e_arg = i - 1
            break
          end
          if source:sub(i, i) == "<" then
            if source:sub(i - 1, i - 1):match("[A-Z]") then
              local _, _, _, e_cmd = findInline(source, i - 1)
              if e_cmd then
                i = e_cmd
              else
                local row, col = indexToRowCol(source, i - 1)
                error(
                  "ERROR:"
                    .. row
                    .. ":"
                    .. col
                    .. ":"
                    .. "Failed to find the end of command '"
                    .. source:sub(i - 1, i)
                    .. "'"
                )
              end
              i = e_cmd or i
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
  return nil
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return PodiumElement[]
local function splitParagraphs(source, startIndex, endIndex)
  startIndex = startIndex or 1 ---@cast startIndex integer
  endIndex = endIndex or #source ---@cast endIndex integer
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
  for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
    if state_list > 0 then
      table.insert(lines, line)
      if line:match("^=over") then
        state_list = state_list + 1
      elseif line:match("^=back") then
        state_list = state_list - 1
      elseif state_list == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = "list", value = join(lines) })
        state_list = 0
        lines = {}
      end
    elseif state_para > 0 then
      table.insert(lines, line)
      if state_para == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = "para", value = join(lines)  })
        state_para = 0
        lines = {}
      end
    elseif state_verb > 0 then
      if state_verb == 1 and line:match("^%S") then
        table.insert(paragraphs, { kind = "verb", value = join(lines)  })
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
        table.insert(paragraphs, { kind = block_name, value = join(lines)  })
        lines = {}
        state_block = 0
      end
    elseif state_cmd > 0 then
      table.insert(lines, line)
      if state_cmd == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = cmd_name, value = join(lines)  })
        lines = {}
        state_cmd = 0
      end
    else
      if line:match("^=over") then
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
      table.insert(paragraphs, { kind = "list", value = join(lines)  })
    elseif state_para > 0 then
      table.insert(paragraphs, { kind = "para", value = join(lines)  })
    elseif state_verb > 0 then
      table.insert(paragraphs, { kind = "verb", value = join(lines)  })
    elseif state_block > 0 then
      table.insert(paragraphs, { kind = block_name, value = join(lines)  })
    elseif state_cmd > 0 then
      table.insert(paragraphs, { kind = cmd_name, value = join(lines)  })
    end
  end
  for _, paragraph in ipairs(paragraphs) do
    paragraph.startIndex = startIndex
    paragraph.endIndex = startIndex + #paragraph.value - 1
    startIndex = paragraph.endIndex + 1
  end
  return paragraphs
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return PodiumElement[]
local function splitItem(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  local state = 0
  ---@type string[]
  local lines = {}
  ---@type PodiumElement[]
  local parts = {}
  for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
    if state == 0 then
      if line:match("^=over") then
        table.insert(parts, { kind = "itempart", value = join(lines) })
        state = state + 2
        lines = { line }
      else
        table.insert(lines, line)
      end
    else
      table.insert(lines, line)
      if line:match("^=over") then
        state = state + 1
      elseif line:match("^=back") then
        state = state - 1
      elseif state == 1 and line:match("^%s+$") then
        table.insert(parts, { kind = "list", value = join(lines) })
        lines = {}
        state = 0
      end
    end
  end
  if #lines > 0 then
    if state > 0 then
      table.insert(parts, { kind = "list", value = join(lines) })
    else
      table.insert(parts, { kind = "itempart", value = join(lines) })
    end
  end
  for _, part in ipairs(parts) do
    part.startIndex = startIndex
    part.endIndex = startIndex + #part.value - 1
    startIndex = part.endIndex + 1
  end
  return parts
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return PodiumElement[]
local function splitItems(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  ---@type PodiumElement[]
  local items = {}
  local state = 'nonitems'
  local allLines = splitLines(source, startIndex, endIndex)
  ---@type string[]
  local lines = {}
  local depth = 0
  local index = 1
  while index <= #allLines do
    local line = allLines[index]
    if state == 'nonitems' then
      if line:match("^=item") then
        if depth == 0 then
          if #lines > 0 then
            local row, col = indexToRowCol(source, startIndex)
            error("ERROR:" .. row .. ":" .. col .. ": non-item lines should not precede an item")
          end
          lines = { line }
          state = 'items'
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
    elseif state == 'items' then
      if line:match("^=item") then
        if depth == 0 then
          table.insert(items, { kind = "item", value = join(lines) })
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
  if state == 'items' then
    table.insert(items, { kind = "item", value = join(lines) })
  else
    return splitParagraphs(source, startIndex, endIndex)
  end
  for _, item in ipairs(items) do
    item.startIndex = startIndex
    item.endIndex = startIndex + #item.value - 1
    startIndex = item.endIndex + 1
  end
  return items
end

---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return PodiumElement[]
local function splitTokens(source, startIndex, endIndex)
  startIndex = startIndex or 1
  endIndex = endIndex or #source
  ---@type PodiumElement[]
  local tokens = {}
  local i = startIndex
  while i <= endIndex do
    local b_cmd, _, _, e_cmd = findInline(source, i, endIndex)
    if b_cmd then
      table.insert(tokens, {
        kind = "text",
        startIndex = i,
        endIndex = b_cmd - 1,
        value = source:sub(i, b_cmd - 1),
      })
      table.insert(tokens, {
        kind = source:sub(b_cmd, b_cmd),
        startIndex = b_cmd,
        endIndex = e_cmd,
        value = source:sub(b_cmd, e_cmd),
      })
      i = e_cmd + 1
    else
      table.insert(tokens, {
        kind = "text",
        startIndex = i,
        endIndex = endIndex,
        value = source:sub(i, endIndex),
      })
      i = endIndex + 1
    end
  end
  return tokens
end


---@param source string
---@param startIndex? integer
---@param endIndex? integer
---@return PodiumElement[]
local function splitList(source, startIndex, endIndex)
  startIndex = startIndex or 1 ---@cast startIndex integer
  endIndex = endIndex or #source ---@cast endIndex integer
  ---@type 'over' | 'items' | 'back'
  local state = "over"
  local lines = splitLines(source, startIndex, endIndex)
  local list_type = 'unordered'
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
    if state == "over" then
      table.insert(over_lines, line)
      if line:match("^%s*$") then
        state = "items"
      end
      index = index + 1
    elseif state == "items" then
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
          state = "back"
        end
      elseif line:match("^=item") then
        if items_depth == 0 then
          if line:match("^=item%s*%d+") then
            list_type = 'ordered'
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
  local over_endIndex = startIndex
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
  return {
    { kind = "over_" .. list_type, startIndex = startIndex, endIndex = over_endIndex, value = join(over_lines) },
    { kind = "items", startIndex = items_startIndex, endIndex = items_endIndex, value = join(items_lines) },
    { kind = "back_" .. list_type, startIndex = back_startIndex, endIndex = back_endIndex, value = join(back_lines) },
  }
end

---@param source string
---@param target PodiumConverter
local function process(source, target)
  local elements = splitParagraphs(source)
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
          target[element.kind](source, element.startIndex, element.endIndex),
          slice(elements, i + 1)
        )
      end
    else
      elements = append(
        slice(elements, 1, i - 1),
        { { kind = "skip", startIndex = element.startIndex, endIndex = element.endIndex, value = "" } },
        slice(elements, i + 1)
      )
      i = i + 1
    end
    if element.kind == "cut" then
      shouldProcess = false
    end
  end
  elements = append(target["preamble"](source, 1, #source), elements, target["postamble"](source, 1, #source))
  local output = ""
  for _, element in ipairs(elements) do
    if element.kind ~= "skip" then
      output = output .. element.value
    end
  end
  return output
end

---@alias PodiumElementKindInlineCmd 'A' | 'B' | 'C' | 'D' | 'E' | 'F' | 'G' | 'H' | 'I' | 'J' | 'K' | 'L' | 'M' | 'N' | 'O' | 'P' | 'Q' | 'R' | 'S' | 'T' | 'U' | 'V' | 'W' | 'X' | 'Y' | 'Z'
---@alias PodiumElementKindBlockCmd 'pod' | 'cut' | 'encoding' | 'over_unordered' | 'over_ordered' | 'item' | 'back_unordered' | 'back_ordered' | 'verb' | 'for' | 'head1' | 'head2' | 'head3' | 'head4'
---@alias PodiumElementKindInternalConstituent  'list' | 'items' | 'itempart' | 'para' | 'text' | 'preamble' | 'postamble' | 'skip'
---@alias PodiumElementKind PodiumElementKindBlockCmd | PodiumElementKindInlineCmd | PodiumElementKindInternalConstituent | string
---@class PodiumElement
---@field kind PodiumElementKind
---@field startIndex integer
---@field endIndex integer
---@field value string

---@alias PodiumIdentifier string
---@alias PodiumConvertElementSource fun(source: string, startIndex?: integer, endIndex?: integer): PodiumElement[]
---@alias PodiumConverter table<PodiumIdentifier, PodiumConvertElementSource>

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
---@return PodiumElement
local function parsed_token(value)
  return { kind = "text", startIndex = -1, endIndex = -1, value = value }
end

local html = rules({
  preamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  postamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  head1 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<h1>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</h1>" .. nl) })
  end,
  head2 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<h2>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</h2>" .. nl) })
  end,
  head3 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<h3>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</h3>" .. nl) })
  end,
  head4 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<h4>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</h4>" .. nl) })
  end,
  para = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<p>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</p>" .. nl) })
  end,
  over_unordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token("<ul>" .. nl) }
  end,
  over_ordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token("<ol>" .. nl) }
  end,
  back_unordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token("</ul>" .. nl) }
  end,
  back_ordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token("</ol>" .. nl) }
  end,
  cut = function(_source, _startIndex, _endIndex)
    return {}
  end,
  pod = function(_source, _startIndex, _endIndex)
    return {}
  end,
  verb = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    return {
      parsed_token("<pre><code>" .. nl),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token("</code></pre>" .. nl),
    }
  end,
  html = function(source, startIndex, endIndex)
    ---@type string[]
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
      if state == 0 then
        if line:match("^=begin") then
          state = 1
        elseif line:match("^=end") then
          state = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(join(lines)) }
  end,
  item = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex = source:sub(1, endIndex):find("^=item%s*[*0-9]*%.?.", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token("<li>") },
      splitItem(source, startIndex, endIndex),
      { parsed_token("</li>" .. nl) }
    )
  end,
  ["for"] = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex = source:sub(1, endIndex):find("=for%s+%S+%s", startIndex)
    return {
      parsed_token("<pre><code>" .. nl),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token("</code></pre>" .. nl),
    }
  end,
  list = function(source, startIndex, endIndex)
    return splitList(source, startIndex, endIndex)
  end,
  items = function(source, startIndex, endIndex)
    return splitItems(source, startIndex, endIndex)
  end,
  itempart = function(source, startIndex, endIndex)
    return splitTokens(source, startIndex, endIndex)
  end,
  I = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<em>") },  splitTokens(source, startIndex, endIndex), { parsed_token("</em>") })
  end,
  B = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token("<strong>") },
      splitTokens(source, startIndex, endIndex),
      { parsed_token("</strong>") }
    )
  end,
  C = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("<code>") }, splitTokens(source, startIndex, endIndex), { parsed_token("</code>") })
  end,
  L = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local b, e = source:sub(1, endIndex):find("[^|]*|", startIndex)
    if b then
      return append(
        { parsed_token('<a href="') },
        splitTokens(source, e + 1, endIndex),
        { parsed_token('">') },
        splitTokens(source, b, e - 1),
        { parsed_token("</a>") }
      )
    else
      return append(
        { parsed_token('<a href="') },
        splitTokens(source, startIndex, endIndex),
        { parsed_token('">') },
        splitTokens(source, startIndex, endIndex),
        { parsed_token("</a>") }
      )
    end
  end,
  E = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local arg = source:sub(startIndex, endIndex)
    return { parsed_token("&" .. arg .. ";") }
  end,
  X = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token('<a name="') },  splitTokens(source, startIndex, endIndex), { parsed_token('"></a>') })
  end,
  Z = function(_source, _startIndex, _endIndex)
    return {}
  end,
})

local markdown_list_level = 0
local markdown = rules({
  preamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  postamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  head1 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({parsed_token("# ") },  splitTokens(source,  startIndex, endIndex),  { parsed_token(nl .. nl) })
  end,
  head2 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("## ") }, splitTokens(source, startIndex, endIndex), { parsed_token(nl .. nl) })
  end,
  head3 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("### ") }, splitTokens(source, startIndex, endIndex), { parsed_token(nl .. nl) })
  end,
  head4 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("#### ") }, splitTokens(source, startIndex, endIndex), { parsed_token(nl .. nl) })
  end,
  para = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(splitTokens(source, startIndex, endIndex), { parsed_token(nl .. nl) })
  end,
  over_unordered = function(_source, _startIndex, _endIndex)
    markdown_list_level = markdown_list_level + 2
    return {}
  end,
  over_ordered = function(_source, _startIndex, _endIndex)
    markdown_list_level = markdown_list_level + 2
    return {}
  end,
  back_unordered = function(source, _startIndex, _endIndex)
    markdown_list_level = markdown_list_level - 2
    local nl = guessNewline(source)
    return { parsed_token(nl) }
  end,
  back_ordered = function(source, _startIndex, _endIndex)
    markdown_list_level = markdown_list_level - 2
    local nl = guessNewline(source)
    return { parsed_token(nl) }
  end,
  cut = function(_source, _startIndex, _endIndex)
    return {}
  end,
  pod = function(_source, _startIndex, _endIndex)
    return {}
  end,
  verb = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    return {
      parsed_token("```" .. nl),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token("```" .. nl .. nl),
    }
  end,
  html = function(source, startIndex, endIndex)
    ---@type string[]
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
      if state == 0 then
        if line:match("^=begin") then
          state = 1
        elseif line:match("^=end") then
          state = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(join(lines)) }
  end,
  item = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    local bullet = "-"
    if source:sub(1, endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = source:sub(1, endIndex):find("^=item%s*([0-9]+%.?)", startIndex)
    end
    _, startIndex = source:sub(1, endIndex):find("^=item%s*[*0-9]*%.?.", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local indent = string.rep(" ", markdown_list_level)
    return append(
      { parsed_token(indent .. bullet .. " ") },
      splitItem(source, startIndex, endIndex),
      { parsed_token(nl) }
    )
  end,
  ["for"] = function(source, startIndex, endIndex)
    _, startIndex = source:sub(1, endIndex):find("=for%s+%S+%s", startIndex)
    local nl = guessNewline(source)
    return {
      parsed_token("```" .. nl),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token("```" .. nl),
    }
  end,
  list = function(source, startIndex, endIndex)
    return splitList(source, startIndex, endIndex)
  end,
  items = function(source, startIndex, endIndex)
    return splitItems(source, startIndex, endIndex)
  end,
  itempart = function(source, startIndex, endIndex)
    return splitTokens(source, startIndex, endIndex)
  end,
  I = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("*") }, splitTokens(source, startIndex, endIndex), { parsed_token("*") })
  end,
  B = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("**") }, splitTokens(source, startIndex, endIndex), { parsed_token("**") })
  end,
  C = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token("`") }, splitTokens(source, startIndex, endIndex), { parsed_token("`") })
  end,
  L = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local b, e = source:sub(1, endIndex):find("[^|]*|", startIndex)
    if b then
      return append(
        { parsed_token("[") },
        splitTokens(source, b, e - 1),
        { parsed_token("](") },
        splitTokens(source, e + 1, endIndex),
        { parsed_token(")") }
      )
    else
      return append(
        { parsed_token("[") },
        splitTokens(source, startIndex, endIndex),
        { parsed_token("](") },
        splitTokens(source, startIndex, endIndex),
        { parsed_token(")") }
      )
    end
  end,
  E = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    if source:sub(startIndex, endIndex) == "lt" then
      return { parsed_token("<") }
    elseif source:sub(startIndex, endIndex) == "gt" then
      return { parsed_token(">") }
    elseif source:sub(startIndex, endIndex) == "verbar" then
      return { parsed_token("|") }
    elseif source:sub(startIndex, endIndex) == "sol" then
      return { parsed_token("/") }
    else
      return { parsed_token("&" .. source:sub(startIndex, endIndex) .. ";") }
    end
  end,
  Z = function(_source, _startIndex, _endIndex)
    return {}
  end,
})

---@param source string
---@param startIndex integer
---@param endIndex integer
---@return PodiumElement[]
local function vimdoc_head(source, startIndex, endIndex)
  local nl = guessNewline(source)
  startIndex = source:sub(1, endIndex):find("%s", startIndex)
  _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
  local tokens = splitTokens(source, startIndex, endIndex)
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
      { { kind = "text", startIndex = -1, endIndex = -1, value = "~" .. nl } },
      { { kind = "text", startIndex = -1, endIndex = -1, value = string.rep(" ", padding) } },
      tags,
      { { kind = "text", startIndex = -1, endIndex = -1, value = nl .. nl } }
    )
  else
    return append(tokens, { { kind = "text", startIndex = -1, endIndex = -1, value = "~" .. nl .. nl } })
  end
end

local vimdoc_list_level = 0
local vimdoc = rules({
  preamble = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    local frontmatter = parseFrontMatter(source)
    local filename = frontmatter.name .. ".txt"
    local description = frontmatter.description
    local spaces = string.rep(" ", 78 - #filename - #description - #nl)
    return {
      {
        kind = "text",
        startIndex = -1,
        endIndex = -1,
        value = filename .. spaces .. description .. nl
      },
    }
  end,
  postamble = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return {
      {
        kind = "text",
        startIndex = -1,
        endIndex = -1,
        value = nl .. "vim:tw=78:ts=8:noet:ft=help:norl:" .. nl
      },
    }
  end,
  head1 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    return append(
      { { kind = "text", startIndex = -1, endIndex = -1, value = string.rep("=", 78 - #nl) .. nl } },
      vimdoc_head(source, startIndex, endIndex)
    )
  end,
  head2 = vimdoc_head,
  head3 = vimdoc_head,
  head4 = vimdoc_head,
  para = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local tokens = splitTokens(source, startIndex, endIndex)
    return append(tokens, { parsed_token(nl .. nl) })
  end,
  over_unordered = function(_source, _startIndex, _endIndex)
    vimdoc_list_level = vimdoc_list_level + 2
    return {}
  end,
  over_ordered = function(_source, _startIndex, _endIndex)
    vimdoc_list_level = vimdoc_list_level + 2
    return {}
  end,
  back_unordered = function(source, _startIndex, _endIndex)
    vimdoc_list_level = vimdoc_list_level - 2
    local nl = guessNewline(source)
    return { parsed_token(nl) }
  end,
  back_ordered = function(source, _startIndex, _endIndex)
    vimdoc_list_level = vimdoc_list_level - 2
    local nl = guessNewline(source)
    return { parsed_token(nl) }
  end,
  cut = function(_source, _startIndex, _endIndex)
    return {}
  end,
  pod = function(_source, _startIndex, _endIndex)
    return {}
  end,
  verb = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    return {
      parsed_token(">" .. nl),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token("<" .. nl .. nl),
    }
  end,
  vimdoc = function(source, startIndex, endIndex)
    ---@type string[]
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
      if state == 0 then
        if line:match("^=begin") then
          state = 1
        elseif line:match("^=end") then
          state = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(join(lines)) }
  end,
  item = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    local bullet = "-"
    if source:sub(1, endIndex):match("^=item%s*[0-9]") then
      _, _, bullet = source:sub(1, endIndex):find("^=item%s*([0-9]+%.?)", startIndex)
    end
    _, startIndex = source:sub(1, endIndex):find("^=item%s*[*0-9]*%.?.", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local indent = string.rep(" ", vimdoc_list_level)
    return append(
      { parsed_token(indent .. bullet .. " ") },
      splitItem(source, startIndex, endIndex),
      { parsed_token(nl) }
    )
  end,
  ["for"] = function(source, startIndex, endIndex)
    _, startIndex = source:sub(1, endIndex):find("=for%s+%S+%s", startIndex)
    local nl = guessNewline(source)
    return {
      parsed_token( "<" .. nl ),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token( ">" .. nl .. nl ),
    }
  end,
  list = function(source, startIndex, endIndex)
    return splitList(source, startIndex, endIndex)
  end,
  items = function(source, startIndex, endIndex)
    return splitItems(source, startIndex, endIndex)
  end,
  itempart = function(source, startIndex, endIndex)
    return splitTokens(source, startIndex, endIndex)
  end,
  C = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "`" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "`" ) })
  end,
  O = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "'" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "'" ) })
  end,
  L = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local b, e = source:sub(1, endIndex):find("[^|]*|", startIndex)
    if b then
      return append(
        splitTokens(source, b, e - 1),
        { parsed_token( " |" ) },
        splitTokens(source, e + 1, endIndex),
        { parsed_token( "|" ) }
      )
    else
      return append({ parsed_token( "|" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "|" ) })
    end
  end,
  X = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "*" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "*" ) })
  end,
  E = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    if source:sub(startIndex, endIndex) == "lt" then
      return { parsed_token( "<" ) }
    elseif source:sub(startIndex, endIndex) == "gt" then
      return { parsed_token( ">" ) }
    elseif source:sub(startIndex, endIndex) == "verbar" then
      return { parsed_token( "|" ) }
    elseif source:sub(startIndex, endIndex) == "sol" then
      return { parsed_token( "/" ) }
    else
      return { parsed_token( "&" .. source:sub(startIndex, endIndex) .. ";" ) }
    end
  end,
  Z = function(_source, _startIndex, _endIndex)
    return {}
  end,
})

local latex = rules({
  preamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  postamble = function(_source, _startIndex, _endIndex)
    return {}
  end,
  head1 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token( "\\section{" ) },
      splitTokens(source, startIndex, endIndex),
      { parsed_token( "}" .. nl ) }
    )
  end,
  head2 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token( "\\subsection{" ) },
      splitTokens(source, startIndex, endIndex),
      { parsed_token( "}" .. nl ) }
    )
  end,
  head3 = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    startIndex = source:sub(1, endIndex):find("%s", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token( "\\subsubsection{" ) },
      splitTokens(source, startIndex, endIndex),
      { parsed_token( "}" .. nl ) }
    )
  end,
  para = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(splitTokens(source, startIndex, endIndex), { parsed_token( nl ) })
  end,
  over_unordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token( "\\begin{itemize}" .. nl ) }
  end,
  over_ordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token( "\\begin{enumerate}" .. nl ) }
  end,
  back_unordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token("\\end{itemize}" .. nl ) }
  end,
  back_ordered = function(source, _startIndex, _endIndex)
    local nl = guessNewline(source)
    return { parsed_token( "\\end{enumerate}" .. nl ) }
  end,
  cut = function(_source, _startIndex, _endIndex)
    return {}
  end,
  pod = function(_source, _startIndex, _endIndex)
    return {}
  end,
  verb = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    return {
      parsed_token( "\\begin{verbatim}" .. nl ),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token( "\\end{verbatim}" .. nl ),
    }
  end,
  latex = function(source, startIndex, endIndex)
    ---@type string[]
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, startIndex, endIndex)) do
      if state == 0 then
        if line:match("^=begin") then
          state = 1
        elseif line:match("^=end") then
          state = 0
        end
      else
        table.insert(lines, line)
      end
    end
    return { parsed_token(join(lines)) }
  end,
  item = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex = source:sub(1, endIndex):find("^=item%s*[*0-9]*%.?.", startIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append(
      { parsed_token( "\\item " ) },
      splitItem(source, startIndex, endIndex),
      { parsed_token( nl ) }
    )
  end,
  ["for"] = function(source, startIndex, endIndex)
    local nl = guessNewline(source)
    _, startIndex = source:sub(1, endIndex):find("=for%s+%S+%s", startIndex)
    return {
      parsed_token( "\\begin{verbatim}" .. nl ),
      parsed_token(source:sub(startIndex, endIndex)),
      parsed_token( "\\end{verbatim}" .. nl ),
    }
  end,
  list = function(source, startIndex, endIndex)
    return splitList(source, startIndex, endIndex)
  end,
  items = function(source, startIndex, endIndex)
    return splitItems(source, startIndex, endIndex)
  end,
  itempart = function(source, startIndex, endIndex)
    return splitTokens(source, startIndex, endIndex)
  end,
  I = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "\\textit{" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "}" ) })
  end,
  B = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "\\textbf{" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "}" ) })
  end,
  C = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "\\verb|" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "|" ) })
  end,
  L = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    local b, e = source:sub(1, endIndex):find("[^|]*|", startIndex)
    if b then
      return append(
        { parsed_token( "\\href{" ) },
        splitTokens(source, e + 1, endIndex),
        { parsed_token( "}{" ) },
        splitTokens(source, b, e - 1),
        { parsed_token( "}" ) }
      )
    elseif source:sub(startIndex, endIndex):match("^https?://") then
      return append({ parsed_token( "\\url{" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "}" ) })
    else
      return {
        { parsed_token( "\\ref{" ) },
        splitTokens(source, startIndex, endIndex),
        { parsed_token( "}" ) },
      }
    end
  end,
  E = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    if source:sub(startIndex, endIndex) == "lt" then
      return { parsed_token( "<" ) }
    elseif source:sub(startIndex, endIndex) == "gt" then
      return { parsed_token( ">" ) }
    elseif source:sub(startIndex, endIndex) == "verbar" then
      return { parsed_token( "|" ) }
    elseif source:sub(startIndex, endIndex) == "sol" then
      return { parsed_token( "/" ) }
    else
      return {
        parsed_token( "\\texttt{" ),
        splitTokens(source, startIndex, endIndex),
        parsed_token( "}" ),
      }
    end
  end,
  X = function(source, startIndex, endIndex)
    _, startIndex, endIndex, _ = findInline(source, startIndex, endIndex)
    _, startIndex, endIndex = trimBlank(source, startIndex, endIndex)
    return append({ parsed_token( "\\label{" ) }, splitTokens(source, startIndex, endIndex), { parsed_token( "}" ) })
  end,
  Z = function(_source, _startIndex, _endIndex)
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
