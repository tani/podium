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
---@param offset? integer
---@param limit? integer
---@return string,integer,integer
local function trimBlank(source, offset, limit)
  -- remove leading blank spaces and tailing blank spaces
  -- and return the new source with the new offset and limit
  offset = offset or 1
  limit = limit or #source
  local i = offset
  while i <= limit do
    if source:sub(i, i):match("%s") then
      i = i + 1
    else
      break
    end
  end
  local j = limit
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
---@param offset? integer
---@param limit? integer
---@return string[]
local function splitLines(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local lines = {}
  local i = offset
  while i <= limit do
    local j = source:sub(1, limit):find("[\r\n]", i)
    if j == nil then
      table.insert(lines, source:sub(i, limit))
      i = limit + 1
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
---@param offset integer
---@return integer,integer
local function offsetToRowCol(source, offset)
  local row = 1
  local col = 1
  local i = 1
  while i < offset do
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
---@param offset? integer
---@param limit? integer
---@return integer|nil,integer?,integer?,integer?
local function findInline(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  for b_cmd = offset, limit do
    if source:sub(b_cmd, b_cmd):match("[A-Z]") then
      if source:sub(b_cmd + 1, b_cmd + 1) == "<" then
        local count = 1
        local space = ""
        local i = b_cmd + 2
        local b_arg, e_arg = nil, nil
        while i <= limit do
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
        if i > limit then
          local row, col = offsetToRowCol(source, b_cmd)
          error("ERROR:" .. row .. ":" .. col .. ": " .. "Missing closing brackets '<" .. string.rep(">", count) .. "'")
        end
        local angles = space .. string.rep(">", count)
        while i <= limit do
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
                local row, col = offsetToRowCol(source, i - 1)
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
        if i > limit then
          local row, col = offsetToRowCol(source, b_cmd)
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
---@return PodiumElement[]
local function splitParagraphs(source)
  local state_list = 0
  local state_para = 0
  local state_verb = 0
  local state_block = 0
  local block_name = ""
  local state_cmd = 0
  local cmd_name = ""
  local paragraphs = {}
  local lines = {}
  for _, line in ipairs(splitLines(source)) do
    if state_list > 0 then
      table.insert(lines, line)
      if line:match("^=over") then
        state_list = state_list + 1
      elseif line:match("^=back") then
        state_list = state_list - 1
      elseif state_list == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = "list", lines = lines })
        state_list = 0
        lines = {}
      end
    elseif state_para > 0 then
      table.insert(lines, line)
      if state_para == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = "para", lines = lines })
        state_para = 0
        lines = {}
      end
    elseif state_verb > 0 then
      if state_verb == 1 and line:match("^%S") then
        table.insert(paragraphs, { kind = "verb", lines = lines })
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
        table.insert(paragraphs, { kind = block_name, lines = lines })
        lines = {}
        state_block = 0
      end
    elseif state_cmd > 0 then
      table.insert(lines, line)
      if state_cmd == 1 and line:match("^%s+$") then
        table.insert(paragraphs, { kind = cmd_name, lines = lines })
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
      table.insert(paragraphs, { kind = "list", lines = lines })
    elseif state_para > 0 then
      table.insert(paragraphs, { kind = "para", lines = lines })
    elseif state_verb > 0 then
      table.insert(paragraphs, { kind = "verb", lines = lines })
    elseif state_block > 0 then
      table.insert(paragraphs, { kind = block_name, lines = lines })
    elseif state_cmd > 0 then
      table.insert(paragraphs, { kind = cmd_name, lines = lines })
    end
  end
  local offset = 1
  for _, paragraph in ipairs(paragraphs) do
    paragraph.offset = offset
    for _, line in ipairs(paragraph.lines) do
      offset = offset + #line
    end
    paragraph.limit = offset - 1
  end
  return paragraphs
end

---@param source string
---@param offset? integer
---@param limit? integer
---@return PodiumElement[]
local function splitItemParts(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local lines = {}
  local state = 0
  local parts = {}
  for _, line in ipairs(splitLines(source, offset, limit)) do
    if state == 0 then
      if line:match("^=over") then
        table.insert(parts, { kind = "part", lines = lines })
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
        table.insert(parts, { kind = "list", lines = lines })
        lines = {}
        state = 0
      end
    end
  end
  if #lines > 0 then
    if state > 0 then
      table.insert(parts, { kind = "list", lines = lines })
    else
      table.insert(parts, { kind = "part", lines = lines })
    end
  end
  for _, part in ipairs(parts) do
    part.offset = offset
    for _, line in ipairs(part.lines) do
      offset = offset + #line
    end
    part.limit = offset - 1
  end
  return parts
end

---@param source string
---@param offset? integer
---@param limit? integer
---@return PodiumElement[]
local function splitItems(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local items = {}
  local state = 0
  local lines = {}
  for _, line in ipairs(splitLines(source, offset, limit)) do
    if state == 0 then
      if line:match("^=item") then
        table.insert(items, { kind = "over", lines = lines })
        state = 1
        lines = { line }
      else
        table.insert(lines, line)
      end
    else
      if state == 1 and line:match("^=item") then
        table.insert(items, { kind = "item", lines = lines })
        lines = { line }
      elseif line:match("^=over") then
        table.insert(lines, line)
        state = state + 1
      elseif line:match("^=back") then
        state = state - 1
        if state == 0 then
          table.insert(items, { kind = "item", lines = lines })
          lines = { line }
        else
          table.insert(lines, line)
        end
      else
        table.insert(lines, line)
      end
    end
  end
  table.insert(items, { kind = "back", lines = lines })
  for _, item in ipairs(items) do
    item.offset = offset
    for _, line in ipairs(item.lines) do
      offset = offset + #line
    end
    item.limit = offset - 1
  end
  return items
end

---@param source string
---@param offset? integer
---@param limit? integer
---@return PodiumElement[]
local function splitTokens(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local tokens = {}
  local i = offset
  while i <= limit do
    local b_cmd, _, _, e_cmd = findInline(source, i, limit)
    if b_cmd then
      table.insert(tokens, {
        kind = "text",
        offset = i,
        limit = b_cmd - 1,
        lines = splitLines(source, i, b_cmd - 1),
      })
      table.insert(tokens, {
        kind = source:sub(b_cmd, b_cmd),
        offset = b_cmd,
        limit = e_cmd,
        lines = splitLines(source, b_cmd, e_cmd),
      })
      i = e_cmd + 1
    else
      table.insert(tokens, {
        kind = "text",
        offset = i,
        limit = limit,
        lines = splitLines(source, i, limit),
      })
      i = limit + 1
    end
  end
  return tokens
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
          target[element.kind](source, element.offset, element.limit),
          slice(elements, i + 1)
        )
      end
    else
      elements = append(
        slice(elements, 1, i - 1),
        { { kind = "skip", lines = element.lines, offset = element.offset, limit = element.limit } },
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
      for _, line in ipairs(element.lines) do
        output = output .. line
      end
    end
  end
  return output
end

---@class PodiumElement
---@field kind string
---@field offset integer
---@field limit integer
---@field lines string[]

---@alias PodiumIdentifier string
---@alias PodiumConvertElementSource fun(source: string, offset: integer, limit: integer): PodiumElement[]
---@alias PodiumConverter table<PodiumIdentifier, PodiumConvertElementSource>

---@param tbl PodiumConverter
---@return PodiumConverter
local function rules(tbl)
  return setmetatable(tbl, {
    __index = function(_table, _key)
      return function(_source, _offset, _limit)
        return {}
      end
    end,
  })
end


local function parsed_token(lines)
  return { kind = "text", offset = -1, limit = -1, lines = lines }
end


local html = rules({
  preamble = function(_source, _offset, _limit)
    return {}
  end,
  postamble = function(_source, _offset, _limit)
    return {}
  end,
  head1 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<h1>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</h1>", nl }) }
    )
  end,
  head2 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<h2>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</h2>", nl }) }
    )
  end,
  head3 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<h3>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</h3>", nl }) }
    )
  end,
  head4 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<h4>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</h4>", nl }) }
    )
  end,
  para = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<p>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</p>", nl }) }
    )
  end,
  over = function(source, offset, _limit)
    local nl = guessNewline(source)
    local _, i = source:find("=item%s*.", offset)
    if source:sub(i, i):match("[0-9]") then
      return { parsed_token({ "<ol>", nl }) }
    else
      return { parsed_token({ "<ul>", nl }) }
    end
  end,
  back = function(source, offset, _limit)
    local nl = guessNewline(source)
    local i = offset
    while i > 0 do
      local _, j = source:find("=item%s*.", i - 1)
      if j then
        i = j
        break
      else
        i = i - 1
      end
    end
    if source:sub(i, i):match("[0-9]") then
      return { parsed_token({ "</ol>", nl }) }
    else
      return { parsed_token({ "</ul>", nl }) }
    end
  end,
  cut = function(_source, _offset, _limit)
    return {}
  end,
  pod = function(_source, _offset, _limit)
    return {}
  end,
  verb = function(source, offset, limit)
    local nl = guessNewline(source)
    return {
      parsed_token({ "<pre><code>", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "</code></pre>", nl })
    }
  end,
  html = function(source, offset, limit)
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, offset, limit)) do
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
    return { parsed_token(lines) }
  end,
  item = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset = source:sub(1, limit):find("^=item%s*[*0-9]*%.?.", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<li>" }) },
      splitItemParts(source, offset, limit),
      { parsed_token({ "</li>", nl }) }
    )
  end,
  ["for"] = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset = source:sub(1, limit):find("=for%s+%S+%s", offset)
    return {
      parsed_token({ "<pre><code>", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "</code></pre>", nl })
    }
  end,
  list = function(source, offset, limit)
    return splitItems(source, offset, limit)
  end,
  part = function(source, offset, limit)
    return splitTokens(source, offset, limit)
  end,
  I = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<em>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</em>" }) }
    )
  end,
  B = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<strong>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</strong>" }) }
    )
  end,
  C = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<code>" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "</code>" }) }
    )
  end,
  L = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    local b, e = source:sub(1, limit):find("[^|]*|", offset)
    if b then
      return append(
        { parsed_token({ "<a href=\"" }) },
        splitTokens(source, e + 1, limit),
        { parsed_token({ "\">" }) },
        splitTokens(source, b, e - 1),
        { parsed_token({ "</a>" }) }
      )
    else
      return append(
        { parsed_token({ "<a href=\"" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "\">" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "</a>" }) }
      )
    end
  end,
  E = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    local arg = source:sub(offset, limit)
    return { parsed_token({ "&" .. arg .. ";" }) }
  end,
  X = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "<a name=\"" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "\"></a>" }) }
    )
  end,
  Z = function(_source, _offset, _limit)
    return {}
  end,
})

local markdown_list_level = 0
local markdown = rules({
  preamble = function(_source, _offset, _limit)
    return {}
  end,
  postamble = function(_source, _offset, _limit)
    return {}
  end,
  head1 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "# " }) },
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  head2 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "## " }) },
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  head3 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "### " }) },
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  head4 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "#### " }) },
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  para = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  over = function(_source, _offset, _limit)
    markdown_list_level = markdown_list_level + 2
    return {}
  end,
  back = function(source, _offset, _limit)
    markdown_list_level = markdown_list_level - 2
    local nl = guessNewline(source)
    return { parsed_token({ nl }) }
  end,
  cut = function(_source, _offset, _limit)
    return {}
  end,
  pod = function(_source, _offset, _limit)
    return {}
  end,
  verb = function(source, offset, limit)
    local nl = guessNewline(source)
    return {
      parsed_token({ "```", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "```", nl, nl })
    }
  end,
  html = function(source, offset, limit)
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, offset, limit)) do
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
    return { parsed_token(lines) }
  end,
  item = function(source, offset, limit)
    local nl = guessNewline(source)
    local bullet = "-"
    if source:sub(1, limit):match("^=item%s*[0-9]") then
      _, _, bullet = source:sub(1, limit):find("^=item%s*([0-9]+%.?)", offset)
    end
    _, offset = source:sub(1, limit):find("^=item%s*[*0-9]*%.?.", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    local indent = string.rep(" ", markdown_list_level - 2)
    return append(
      { parsed_token({ indent, bullet, " " }) },
      splitItemParts(source, offset, limit),
      { parsed_token({ nl }) }
    )
  end,
  ["for"] = function(source, offset, limit)
    _, offset = source:sub(1, limit):find("=for%s+%S+%s", offset)
    local nl = guessNewline(source)
    return {
      parsed_token({ "```", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "```", nl })
    }
  end,
  list = function(source, offset, limit)
    return splitItems(source, offset, limit)
  end,
  part = function(source, offset, limit)
    return splitTokens(source, offset, limit)
  end,
  I = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "*" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "*" }) }
    )
  end,
  B = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "**" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "**" }) }
    )
  end,
  C = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "`" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "`" }) }
    )
  end,
  L = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    local b, e = source:sub(1, limit):find("[^|]*|", offset)
    if b then
      return append(
        { parsed_token({ "[" }) },
        splitTokens(source, b, e - 1),
        { parsed_token({ "](" }) },
        splitTokens(source, e + 1, limit),
        { parsed_token({ ")" }) }
      )
    else
      return append(
        { parsed_token({ "[" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "](" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ ")" }) }
      )
    end
  end,
  E = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    if source:sub(offset, limit) == "lt" then
      return { parsed_token({ "<" }) }
    elseif source:sub(offset, limit) == "gt" then
      return { parsed_token({ ">" }) }
    elseif source:sub(offset, limit) == "verbar" then
      return { parsed_token({ "|" }) }
    elseif source:sub(offset, limit) == "sol" then
      return { parsed_token({ "/" }) }
    else
      return { parsed_token({ "&" .. source:sub(offset, limit) .. ";" }) }
    end
  end,
  Z = function(_source, _offset, _limit)
    return {}
  end,
})

---@param source string
---@param offset integer
---@param limit integer
---@return PodiumElement[]
local function vimdoc_head(source, offset, limit)
  local nl = guessNewline(source)
  offset = source:sub(1, limit):find("%s", offset)
  _, offset, limit = trimBlank(source, offset, limit)
  local tokens = splitTokens(source, offset, limit)
  local tags = {}
  local padding = 78
  for i, token in ipairs(tokens) do
    if token.kind == "X" then
      padding = padding - #token.lines[1]
      table.remove(tokens, i)
      table.insert(tags, token)
    end
  end
  if #tags > 0 then
    return append(
      tokens,
      { { kind = "text", offset = -1, limit = -1, lines = { "~", nl } } },
      { { kind = "text", offset = -1, limit = -1, lines = { string.rep(" ", padding) } } },
      tags,
      { { kind = "text", offset = -1, limit = -1, lines = { nl, nl } } }
    )
  else
    return append(tokens, { { kind = "text", offset = -1, limit = -1, lines = { "~", nl, nl } } })
  end
end

local vimdoc_list_level = 0
local vimdoc = rules({
  preamble = function(source, _offset, _limit)
    local nl = guessNewline(source)
    local frontmatter = parseFrontMatter(source)
    local filename = frontmatter.name .. ".txt"
    local description = frontmatter.description
    local spaces = string.rep(" ", 78 - #filename - #description - #nl)
    return {
      {
        kind = "text",
        offset = -1,
        limit = -1,
        lines = {
          filename,
          spaces,
          description,
          nl,
        },
      },
    }
  end,
  postamble = function(source, _offset, _limit)
    local nl = guessNewline(source)
    return {
      {
        kind = "text",
        offset = -1,
        limit = -1,
        lines = {
          nl,
          "vim:tw=78:ts=8:noet:ft=help:norl:" .. nl,
        },
      },
    }
  end,
  head1 = function(source, offset, limit)
    local nl = guessNewline(source)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { string.rep("=", 78 - #nl), nl } } },
      vimdoc_head(source, offset, limit)
    )
  end,
  head2 = vimdoc_head,
  head3 = vimdoc_head,
  head4 = vimdoc_head,
  para = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      splitTokens(source, offset, limit),
      { parsed_token({ nl, nl }) }
    )
  end,
  over = function(_source, _offset, _limit)
    vimdoc_list_level = vimdoc_list_level + 2
    return {}
  end,
  back = function(_source, _offset, _limit)
    vimdoc_list_level = vimdoc_list_level - 2
    return {}
  end,
  cut = function(_source, _offset, _limit)
    return {}
  end,
  pod = function(_source, _offset, _limit)
    return {}
  end,
  verb = function(source, offset, limit)
    local nl = guessNewline(source)
    return {
      parsed_token({ ">", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "<", nl, nl })
    }
  end,
  vimdoc = function(source, offset, limit)
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, offset, limit)) do
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
    return { parsed_token(lines) }
  end,
  item = function(source, offset, limit)
    local nl = guessNewline(source)
    local bullet = "-"
    if source:sub(1, limit):match("^=item%s*[0-9]") then
      _, _, bullet = source:sub(1, limit):find("^=item%s*([0-9]+%.?)", offset)
    end
    _, offset = source:sub(1, limit):find("^=item%s*[*0-9]*%.?.", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    local indent = string.rep(" ", vimdoc_list_level - 2)
    return append(
      { parsed_token({ indent, bullet, " " }) },
      splitItemParts(source, offset, limit),
      { parsed_token({ nl }) }
    )
  end,
  ["for"] = function(source, offset, limit)
    _, offset = source:sub(1, limit):find("=for%s+%S+%s", offset)
    local nl = guessNewline(source)
    return {
      parsed_token({ "<", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ ">", nl, nl })
    }
  end,
  list = function(source, offset, limit)
    return splitItems(source, offset, limit)
  end,
  part = function(source, offset, limit)
    return splitTokens(source, offset, limit)
  end,
  C = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "`" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "`" }) }
    )
  end,
  O = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "'" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "'" }) }
    )
  end,
  L = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    local b, e = source:sub(1, limit):find("[^|]*|", offset)
    if b then
      return append(
        splitTokens(source, b, e - 1),
        { parsed_token({ " |" }) },
        splitTokens(source, e + 1, limit),
        { parsed_token({ "|" }) }
      )
    else
      return append(
        { parsed_token({ "|" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "|" }) }
      )
    end
  end,
  X = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "*" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "*" }) }
    )
  end,
  E = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    if source:sub(offset, limit) == "lt" then
      return { parsed_token({ "<" }) }
    elseif source:sub(offset, limit) == "gt" then
      return { parsed_token({ ">" }) }
    elseif source:sub(offset, limit) == "verbar" then
      return { parsed_token({ "|" }) }
    elseif source:sub(offset, limit) == "sol" then
      return { parsed_token({ "/" }) }
    else
      return { parsed_token({ "&" .. source:sub(offset, limit) .. ";" }) }
    end
  end,
  Z = function(_source, _offset, _limit)
    return {}
  end,
})

local latex = rules({
  preamble = function(_source, _offset, _limit)
    return {}
  end,
  postamble = function(_source, _offset, _limit)
    return {}
  end,
  head1 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ nl,  "\\section{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}", nl }) }
    )
  end,
  head2 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ nl,  "\\subsection{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}", nl }) }
    )
  end,
  head3 = function(source, offset, limit)
    local nl = guessNewline(source)
    offset = source:sub(1, limit):find("%s", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ nl,  "\\subsubsection{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}", nl }) }
    )
  end,
  para = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      splitTokens(source, offset, limit),
      { parsed_token({ nl }) }
    )
  end,
  over = function(source, offset, _limit)
    local nl = guessNewline(source)
    local _, i = source:find("=item%s*.", offset)
    if source:sub(i, i):match("[0-9]")  then
      return { parsed_token({ nl,  "\\begin{enumerate}" }) }
    else
      return { parsed_token({ nl,  "\\begin{itemize}" }) }
    end
  end,
  back = function(source, offset, _limit)
    local nl = guessNewline(source)
    local i = offset
    while i > 0 do
      local _, j = source:find("=item%s*.", i - 1)
      if j then
        i = j
        break
      else
        i = i - 1
      end
    end
    if source:sub(i, i):match("[0-9]") then
      return { parsed_token({ nl,  "\\end{enumerate}", nl }) }
    else
      return { parsed_token({ nl,  "\\end{itemize}", nl }) }
    end
  end,
  cut = function(_source, _offset, _limit)
    return {}
  end,
  pod = function(_source, _offset, _limit)
    return {}
  end,
  verb = function(source, offset, limit)
    local nl = guessNewline(source)
    return {
      parsed_token({ nl,  "\\begin{verbatim}", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "\\end{verbatim}", nl }),
    }
  end,
  latex = function(source, offset, limit)
    local lines = {}
    local state = 0
    for _, line in ipairs(splitLines(source, offset, limit)) do
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
    return { parsed_token(lines) }
  end,
  item = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset = source:sub(1, limit):find("^=item%s*[*0-9]*%.?.", offset)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ nl,  "\\item " }) },
      splitItemParts(source, offset, limit)
    )
  end,
  ["for"] = function(source, offset, limit)
    local nl = guessNewline(source)
    _, offset = source:sub(1, limit):find("=for%s+%S+%s", offset)
    return {
      parsed_token({ nl,  "\\begin{verbatim}", nl }),
      parsed_token(splitLines(source, offset, limit)),
      parsed_token({ "\\end{verbatim}", nl }),
    }
  end,
  list = function(source, offset, limit)
    return splitItems(source, offset, limit)
  end,
  part = function(source, offset, limit)
    return splitTokens(source, offset, limit)
  end,
  I = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "\\textit{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}" }) }
    )
  end,
  B = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "\\textbf{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}" }) }
    )
  end,
  C = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "\\verb|" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "|" }) }
    )
  end,
  L = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    local b, e = source:sub(1, limit):find("[^|]*|", offset)
    if b then
      return append(
        { parsed_token({ "\\href{" }) },
        splitTokens(source, e + 1, limit),
        { parsed_token({ "}{" }) },
        splitTokens(source, b, e - 1),
        { parsed_token({ "}" }) }
      )
    elseif source:sub(offset, limit):match("^https?://") then
      return append(
        { parsed_token({ "\\url{" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "}" }) }
      )
    else
      return {
        { parsed_token({ "\\ref{" }) },
        splitTokens(source, offset, limit),
        { parsed_token({ "}" }) },
      }
    end
  end,
  E = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    if source:sub(offset, limit) == "lt" then
      return { parsed_token({ "<" }) }
    elseif source:sub(offset, limit) == "gt" then
      return { parsed_token({ ">" }) }
    elseif source:sub(offset, limit) == "verbar" then
      return { parsed_token({ "|" }) }
    elseif source:sub(offset, limit) == "sol" then
      return { parsed_token({ "/" }) }
    else
      return {
        parsed_token({ "\\texttt{" }),
        splitTokens(source, offset, limit),
        parsed_token({ "}" })
      }
    end
  end,
  X = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    _, offset, limit = trimBlank(source, offset, limit)
    return append(
      { parsed_token({ "\\label{" }) },
      splitTokens(source, offset, limit),
      { parsed_token({ "}" }) }
    )
  end,
  Z = function(_source, _offset, _limit)
    return {}
  end,
})

---@param source string
---@param offset? integer
---@param limit? integer
---@return string
function M.arg(source, offset, limit)
  local _, b, e, _ = findInline(source, offset, limit)
  if b then
    return source:sub(b, e)
  else
    return ""
  end
end

---@param source string
---@param offset? integer
---@param limit? integer
---@return string
function M.body(source, offset, limit)
  local nl = guessNewline(source)
  local _, e = source:sub(1, limit):find("^=begin.*" .. nl, offset)
  local _, f = source:sub(1, limit):find(nl .. "=end.*$", offset)
  return source:sub(e + 1, f - 1)
end

M.splitLines = splitLines
M.splitParagraphs = splitParagraphs
M.splitItemParts = splitItemParts
M.splitItems = splitItems
M.findInline = findInline
M.splitTokens = splitTokens
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
