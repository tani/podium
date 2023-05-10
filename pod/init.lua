-- processr of plain old documentation (POD) format.


local M = {}


local function guessNewline(source)
  local i = 1
  while i <= #source do
    local c = source:sub(i, i)
    if c == '\n' then
      return '\n'
    elseif c == '\r' then
      if source:sub(i + 1, i + 1) == '\n' then
        return '\r\n'
      else
        return '\r'
      end
    end
    i = i + 1
  end
  return '\n'
end


local function splitLines(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local newline = guessNewline(source)
  local lines = {}
  local i = offset
  while i <= limit do
    local j = source:sub(1, limit):find("[\r\n]", i)
    if j == nil then
      table.insert(lines, source:sub(i, limit))
      i = limit + 1
    else
      if source:sub(j, j) == "\r" then
        if source:sub(j+1, j+1) == "\n" then
          j = j +  1
        end
      end
      table.insert(lines, source:sub(i, j))
      i = j + 1
    end
  end
  return lines
end


local function offsetToRowCol(source, offset)
  local row = 1
  local col = 1
  local i = 1
  while i < offset do
    local c = source:sub(i, i)
    if c == '\n' then
      row = row + 1
      col = 1
    elseif c == '\r' then
      row = row + 1
      col = 1
      if source:sub(i + 1, i + 1) == '\n' then
        i = i + 1
      end
    else
      col = col + 1
    end
    i = i + 1
  end
  return row, col
end


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
          error("Missing closing brackets '<" .. string.rep(">", count) ..
                "':" .. row .. ":" .. col .. ": " .. source:sub(b_cmd, b_cmd + count))
        end
        local angles = space .. string.rep(">", count)
        while i <= limit do
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
        if i > limit then
          local row, col = offsetToRowCol(source, b_cmd)
          error("Missing closing brackets '" .. string.rep(">", count) ..
                "':" .. row .. ":" .. col .. ": " .. source:sub(b_cmd, b_cmd + count))
        end
        return b_cmd, b_arg, e_arg, i + #angles - 1
      end
    end
  end
  return nil
end


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
        lines = {line}
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
  offset = 1
  for _, lines in ipairs(paragraphs) do
    lines.offset = offset
    for _, line in ipairs(lines.lines) do
      offset = offset + #line
    end
    lines.limit = offset - 1
  end
  return paragraphs
end


local function splitItemParts(source, offset, limit)
  local lines = {}
  local state = 0
  local parts = {}
  for _, line in ipairs(splitLines(source, offset, limit)) do
    if state == 0 then
      if line:match("^=over") then
        table.insert(parts, { kind = "part", lines = lines })
        state = state + 2
        lines = {line}
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
  offset = 1
  for _, part in ipairs(parts) do
    part.offset = offset
    for _, line in ipairs(part.lines) do
      offset = offset + #line
    end
    part.limit = offset - 1
  end
  return parts
end


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
    elseif state >= 1 then
      if line:match("^=item") then
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
  offset = 1
  for _, item in ipairs(items) do
    item.offset = offset
    for _, line in ipairs(item.lines) do
      offset = offset + #line
    end
    item.limit = offset - 1
  end
  return items
end


local function splitTokens(source, offset, limit)
  offset = offset or 1
  limit = limit or #source
  local tokens = {}
  local lines = {}
  local i = offset
  while i <= limit do
    local b_cmd, b_arg, e_arg, e_cmd = findInline(source, i, limit)
    if b_cmd then
      table.insert(tokens, {
        kind = "text",
        offset = i,
        limit = b_cmd - 1,
        lines = splitLines(source, i, b_cmd - 1)
      })
      table.insert(tokens, {
        kind = source:sub(b_cmd, b_cmd),
        offset = b_arg,
        limit = e_arg,
        lines = splitLines(source, b_cmd, e_cmd)
      })
      i = e_cmd + 1
    else
      table.insert(tokens, {
        kind = "text",
        offset = i,
        limit = limit,
        lines = splitLines(source, i, limit)
      })
      i = limit + 1
    end
  end
  return tokens
end


local function slice(t, i, j)
  i = i and i > 0 and i or 1
  j = j and j <= #t and j or #t
  local r = {}
  for k = i, j do
    table.insert(r, t[k])
  end
  return r
end


local function append(t, ...)
  local r = {}
  for _, v in ipairs(t) do
    table.insert(r, v)
  end
  for _, v in ipairs({...}) do
    for _, v in ipairs(v) do
      table.insert(r, v)
    end
  end
  return r
end


local function process(source)
  local elements = splitParagraphs(source)
  local i = 1
  while i <= #elements do
    local element = elements[i]
    if element.kind == "text" then
      i = i + 1
    else
      elements = append(
        slice(elements, 1, i - 1),
        transform[element.kind](source, element.offset, element.limit),
        slice(elements, i + 1)
      )
    end
  end
  for _, element in ipairs(elements) do
    for _, line in ipairs(element.lines) do
      print(line)
    end
  end
end


local transform = {
  head1 = function(source, offset, limit)
    offset = source:find("%s", offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<h1>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</h1>" } } }
    )
  end,
  head2 = function(source, offset, limit)
    offset = source:find("%s", offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<h2>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</h2>" } } }
    )
  end,
  head3 = function(source, offset, limit)
    offset = source:find("%s", offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<h3>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</h3>" } } }
    )
  end,
  head4 = function(source, offset, limit)
    offset = source:find("%s", offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<h4>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</h4>" } } }
    )
  end,
  para = function(source, offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<p>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</p>" } } }
    )
  end,
  over = function(source, offset, limit)
    return {
      { kind = "text", offset = -1, limit = -1, lines = { "<ul>" } }
    }
  end,
  back = function(source, offset, limit)
    return {
      { kind = "text", offset = -1, limit = -1, lines = { "</ul>" } }
    }
  end,
  cut = function(source, offset, limit)
    return {}
  end,
  pod = function(source, offset, limit)
    return {}
  end,
  verb = function(source, offset, limit)
    return {
      { kind = "text", offset = -1, limit = -1, lines = { "<code><pre>" } },
      { kind = "text", offset = -1, limit = -1, lines = splitLines(source, offset, limit) },
      { kind = "text", offset = -1, limit = -1, lines = { "</pre></code>" } }
    }
  end,
  html = function(source, offset, limit)
    local lines = {}
    local state = 0
    for line in splitLines(source, offset, limit) do
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
    return {
      { kind = "text", offset = -1, limit = -1, lines = lines }
    }
  end,
  item = function(source, offset, limit)
    _, offset = source:find("=item%s+[*0-9]*%.?.", offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<li>" } } },
      splitItemParts(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</li>" } } }
    )
  end,
  ["for"] = function(source, offset, limit)
    _, offset = source:find("=for%s+%S+%s", offset, limit)
    return {
      { kind = "text", offset = -1, limit = -1, lines = { "<code><pre>" } },
      { kind = "text", offset = -1, limit = -1, lines = splitLines(source, offset, limit) },
      { kind = "text", offset = -1, limit = -1, lines = { "</pre></code>" } }
    }
  end,
  para = function(source, offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<p>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</p>" } } }
    )
  end,
  list = function(source, offset, limit)
    return splitItems(source, offset, limit)
  end,
  part = function(source, offset, limit)
    return splitTokens(source, offset, limit)
  end,
  B = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<b>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</b>" } } }
    )
  end,
  C = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    return append(
      { { kind = "text", offset = -1, limit = -1, lines = { "<code>" } } },
      splitTokens(source, offset, limit),
      { { kind = "text", offset = -1, limit = -1, lines = { "</code>" } } }
    )
  end,
  L = function(source, offset, limit)
    _, offset, limit, _ = findInline(source, offset, limit)
    local b, e, text, url = source:find("([^|]*)|(.*)", offset, limit)
    if b then
      return append(
        { { kind = "text", offset = -1, limit = -1, lines = { "<a href=\"" } } },
        splitTokens(source, b, e),
        { { kind = "text", offset = -1, limit = -1, lines = { "\">" } } },
        splitTokens(source, b, e),
        { { kind = "text", offset = -1, limit = -1, lines = { "</a>" } } }
      )
    else
      return {
        { { kind = "text", offset = -1, limit = -1, lines = { "<a href=\"" } } },
        splitTokens(source, offset, limit),
        { { kind = "text", offset = -1, limit = -1, lines = { "\">" } } },
        splitTokens(source, offset, limit),
        { kind = "text", offset = -1, limit = -1, lines = { "</a>" } }
      }
    end
  end,
  E = function(source, offset, limit)
    -- escape
    _, offset, limit, _ = findInline(source, offset, limit)
    arg = source:sub(offset, limit)
    return {
      { kind = "text", offset = -1, limit = -1, lines = { "&" .. arg .. ";" } }
    }
  end
}


M.splitLines = splitLines
M.splitParagraphs = splitParagraphs
M.splitItemParts = splitItemParts
M.splitItems = splitItems
M.findInline = findInline
M.splitTokens = splitTokens
M.process = process
M.transform = transform


return M
