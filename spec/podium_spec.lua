local pod = require("./podium")

local function unindent(str)
  local lines = pod.splitLines(pod.PodiumElement.new(str))
  local indent = lines[1]:match("^%s*")
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^" .. indent, "")
  end
  return table.concat(lines)
end

describe("POD Parser", function()
  describe(":trim", function()
    it("trims string", function()
      local source = "  foo  "
      local actual = pod.PodiumElement.new(source):trim().value
      local expected = "foo"
      assert.are.same(expected, actual)
    end)
    it("trims string with newline", function()
      local source = "  foo \n "
      local actual = pod.PodiumElement.new(source):trim().value
      local expected = "foo"
      assert.are.same(expected, actual)
    end)
  end)
  describe("findFormattingCode", function()
    it("finds formatting code", function()
      local source = "C<bar>"
      local b_cmd, b_arg, e_arg, e_cmd =
        pod.findFormattingCode(pod.PodiumElement.new(source))
      assert.are.same({ 1, 3, 5, 6 }, { b_cmd, b_arg, e_arg, e_cmd })
    end)
  end)
  describe("findDataParagraph", function()
    it("finds data paragraph", function()
      local source = unindent([[
      =begin html

      <p>This is html paragraph</p>

      =end html
      ]])
      local b_cmd, b_arg, e_arg, e_cmd =
        pod.findDataParagraph(pod.PodiumElement.new(source))
      assert.are.same({ 1, 12, 45, 54 }, { b_cmd, b_arg, e_arg, e_cmd })
    end)
  end)
  describe("splitList function", function()
    it("splits simple indent block with default indent", function()
      local source = unindent([[
      =over

      hoge

      =back
      ]])
      local actual = pod.splitList(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "over",
          value = unindent([[
          =over

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 7,
          indentLevel = 4,
          extraProps = { listStyle = "unordered" },
        },
        {
          kind = "items",
          value = unindent([[
          hoge

          ]]),
          source = source,
          startIndex = 8,
          endIndex = 13,
          indentLevel = 4,
          extraProps = {},
        },
        {
          kind = "backspace",
          source = source,
          startIndex = 1,
          endIndex = 19,
          indentLevel = 0,
          extraProps = { deleteCount = 4 },
          value = source,
        },
        {
          kind = "back",
          value = unindent([[
          =back
          ]]),
          source = source,
          startIndex = 14,
          endIndex = 19,
          indentLevel = 0,
          extraProps = { listStyle = "unordered" },
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits simple indent block", function()
      local source = unindent([[
      =over 8

      hoge

      =back
      ]])
      local actual = pod.splitList(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "over",
          value = unindent([[
          =over 8

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 9,
          indentLevel = 8,
          extraProps = { listStyle = "unordered" },
        },
        {
          kind = "items",
          value = unindent([[
          hoge

          ]]),
          source = source,
          startIndex = 10,
          endIndex = 15,
          indentLevel = 8,
          extraProps = {},
        },
        {
          kind = "backspace",
          source = source,
          startIndex = 1,
          endIndex = 21,
          indentLevel = 0,
          extraProps = { deleteCount = 8 },
          value = source,
        },
        {
          kind = "back",
          value = unindent([[
          =back
          ]]),
          source = source,
          startIndex = 16,
          endIndex = 21,
          indentLevel = 0,
          extraProps = { listStyle = "unordered" },
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits nested indent block", function()
      local source = unindent([[
      =over 8

      hoge

      =over 4

      =item fuga

      =back

      =back
      ]])
      local actual = pod.splitList(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "over",
          value = unindent([[
          =over 8

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 9,
          indentLevel = 8,
          extraProps = { listStyle = "unordered" },
        },
        {
          kind = "items",
          value = unindent([[
          hoge

          =over 4

          =item fuga

          =back

          ]]),
          source = source,
          startIndex = 10,
          endIndex = 43,
          indentLevel = 8,
          extraProps = {},
        },
        {
          kind = "backspace",
          source = source,
          startIndex = 1,
          endIndex = 49,
          indentLevel = 0,
          extraProps = { deleteCount = 8 },
          value = source,
        },
        {
          kind = "back",
          value = unindent([[
          =back
          ]]),
          source = source,
          startIndex = 44,
          endIndex = 49,
          indentLevel = 0,
          extraProps = { listStyle = "unordered" },
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitLines function", function()
    it("splits lines by \\n", function()
      local source = "foo\nbar\nbazz"
      local actual = pod.splitLines(pod.PodiumElement.new(source))
      local expected = { "foo\n", "bar\n", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by \\r", function()
      local source = "foo\rbar\rbazz"
      local actual = pod.splitLines(pod.PodiumElement.new(source))
      local expected = { "foo\r", "bar\r", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by \\r\\n", function()
      local source = "foo\r\nbar\r\nbazz"
      local actual = pod.splitLines(pod.PodiumElement.new(source))
      local expected = { "foo\r\n", "bar\r\n", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by mixed newline characters", function()
      local source = "foo\r\nbar\rbazz\nhoge"
      local actual = pod.splitLines(pod.PodiumElement.new(source))
      local expected = { "foo\r\n", "bar\r", "bazz\n", "hoge" }
      assert.are.same(expected, actual)
    end)
  end)

  describe("splitParagraphs function", function()
    it("splits headings", function()
      local source = unindent([[
      =head1 foo


      =head2 hoge

      =head3 bar

      bar
      ]])
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "head1",
          value = unindent([[
          =head1 foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 12,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "head2",
          value = unindent([[
          =head2 hoge

          ]]),
          source = source,
          startIndex = 14,
          endIndex = 26,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "head3",
          value = unindent([[
          =head3 bar

          ]]),
          source = source,
          startIndex = 27,
          endIndex = 38,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "bar\n",
          source = source,
          startIndex = 39,
          endIndex = 42,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by empty line", function()
      local source = "foo\n\nbar\n\nbazz"
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 5,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = unindent([[
          bar

          ]]),
          source = source,
          startIndex = 6,
          endIndex = 10,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "bazz",
          source = source,
          startIndex = 11,
          endIndex = 14,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by over-back block", function()
      local source = unindent([[
      foo

      =over

      =item bar

      =item bazz

      =back

      hoge]])
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 5,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "list",
          value = unindent([[
          =over

          =item bar

          =item bazz

          =back

          ]]),
          source = source,
          startIndex = 6,
          endIndex = 42,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "hoge",
          source = source,
          startIndex = 43,
          endIndex = 46,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by nested over-back block", function()
      local source = unindent([[
        foo

        =over

        =item bar

        =over

        =item bazz

        =back

        =item hoge

        =back

        fuga]])
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 5,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "list",
          value = unindent([[
          =over

          =item bar

          =over

          =item bazz

          =back

          =item hoge

          =back

          ]]),
          source = source,
          startIndex = 6,
          endIndex = 68,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "fuga",
          source = source,
          startIndex = 69,
          endIndex = 72,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by begin-end block", function()
      local source = unindent([[
      foo

      =begin html

      <p>bar</p>

      =end html

      bar]])
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 5,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "html",
          value = unindent([[
          =begin html

          <p>bar</p>

          =end html

          ]]),
          source = source,
          startIndex = 6,
          endIndex = 41,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "bar",
          source = source,
          startIndex = 42,
          endIndex = 44,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("does not split lines with no empty line", function()
      local source = "foo\nbar\nbazz"
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo
          bar
          bazz]]),
          source = source,
          startIndex = 1,
          endIndex = 12,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("does not split lines with no empty line", function()
      local source = unindent([[
        foo

        =over

        =item bar

        =item bazz

        =back
        hoge]])
      local actual = pod.splitParagraphs(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 5,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "list",
          value = unindent([[
          =over

          =item bar

          =item bazz

          =back
          hoge]]),
          source = source,
          startIndex = 6,
          endIndex = 45,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitItems function", function()
    it("split no items", function()
      local source = unindent([[
        lorem ipsum
        dolor sit amet]])
      local actual = pod.splitItems(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          lorem ipsum
          dolor sit amet]]),
          source = source,
          startIndex = 1,
          endIndex = 26,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split no items with list", function()
      local source = unindent([[
        lorem ipsum

        =over
        =item hoge
        =item fuga
        =back

        dolor sit amet]])
      local actual = pod.splitItems(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          lorem ipsum

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 13,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "list",
          value = unindent([[
          =over
          =item hoge
          =item fuga
          =back

          ]]),
          source = source,
          startIndex = 14,
          endIndex = 48,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "para",
          value = "dolor sit amet",
          source = source,
          startIndex = 49,
          endIndex = 62,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split items", function()
      local source = unindent([[
        =item foo

        =item bar

        =item bazz]])
      local actual = pod.splitItems(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "item",
          value = unindent([[
          =item foo

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 11,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "item",
          value = unindent([[
          =item bar

          ]]),
          source = source,
          startIndex = 12,
          endIndex = 22,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "item",
          value = unindent([[
          =item bazz]]),
          source = source,
          startIndex = 23,
          endIndex = 32,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split items with nested list", function()
      local source = unindent([[
        =item foo

        =over
        =item bar

        =item bazz
        =back

        =item hoge]])
      local actual = pod.splitItems(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "item",
          value = unindent([[
          =item foo

          =over
          =item bar

          =item bazz
          =back

          ]]),
          source = source,
          startIndex = 1,
          endIndex = 46,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "item",
          value = "=item hoge",
          source = source,
          startIndex = 47,
          endIndex = 56,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
  end)

  describe("splitItem function", function()
    it("split parts", function()
      local source = "=item foo bar"
      local actual = pod.splitItem(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "itempart",
          value = "=item foo bar",
          source = source,
          startIndex = 1,
          endIndex = 13,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits parts with begin - end", function()
      local source = unindent([[
        =item foo
        bar
        =over
        =item
        =back

        bazz]])
      local actual = pod.splitItem(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "itempart",
          value = unindent([[
          =item foo
          bar
          ]]),
          source = source,
          startIndex = 1,
          endIndex = 14,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "list",
          value = unindent([[
          =over
          =item
          =back

          ]]),
          source = source,
          startIndex = 15,
          endIndex = 33,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "itempart",
          value = "bazz",
          source = source,
          startIndex = 34,
          endIndex = 37,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitTokens function", function()
    it("split tokens without cmd", function()
      local source = "foo bar"
      local actual = pod.splitTokens(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "text",
          value = "foo bar",
          source = source,
          startIndex = 1,
          endIndex = 7,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split tokens with cmd", function()
      local source = "foo bar C<hoge> huga"
      local actual = pod.splitTokens(pod.PodiumElement.new(source))
      local expected = {
        {
          kind = "text",
          value = "foo bar ",
          source = source,
          startIndex = 1,
          endIndex = 8,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "C",
          value = "C<hoge>",
          source = source,
          startIndex = 9,
          endIndex = 15,
          indentLevel = 0,
          extraProps = {},
        },
        {
          kind = "text",
          value = " huga",
          source = source,
          startIndex = 16,
          endIndex = 20,
          indentLevel = 0,
          extraProps = {},
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
end)
