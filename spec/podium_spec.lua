local pod = require("./podium")

local function unindent(str)
  local lines = pod.splitLines(str)
  local indent = lines[1]:match("^%s*")
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^" .. indent, "")
  end
  return table.concat(lines)
end

describe("POD Parser", function()
  describe("splitList function", function()
    it("splits simple indent block", function()
      local content = unindent([[
      =over 8

      hoge

      =back
      ]])
      local actual = pod.splitList(content)
      local expected = {
        {
          kind = "over_unordered",
          value = unindent([[
          =over 8

          ]]),
          startIndex = 1,
          endIndex = 9,
        },
        {
          kind = "items",
          value = unindent([[
          hoge

          ]]),
          startIndex = 10,
          endIndex = 15,
        },
        {
          kind = "back_unordered",
          value = unindent([[
          =back
          ]]),
          startIndex = 16,
          endIndex = 21,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits nested indent block", function()
      local content = unindent([[
      =over 8

      hoge

      =over 4

      =item fuga

      =back

      =back
      ]])
      local actual = pod.splitList(content)
      local expected = {
        {
          kind = "over_unordered",
          value = unindent([[
          =over 8

          ]]),
          startIndex = 1,
          endIndex = 9,
        },
        {
          kind = "items",
          value = unindent([[
          hoge

          =over 4

          =item fuga

          =back

          ]]),
          startIndex = 10,
          endIndex = 43,
        },
        {
          kind = "back_unordered",
          value = unindent([[
          =back
          ]]),
          startIndex = 44,
          endIndex = 49,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitLines function", function()
    it("splits lines by \\n", function()
      local actual = pod.splitLines("foo\nbar\nbazz")
      local expected = { "foo\n", "bar\n", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by \\r", function()
      local actual = pod.splitLines("foo\rbar\rbazz")
      local expected = { "foo\r", "bar\r", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by \\r\\n", function()
      local actual = pod.splitLines("foo\r\nbar\r\nbazz")
      local expected = { "foo\r\n", "bar\r\n", "bazz" }
      assert.are.same(expected, actual)
    end)
    it("splits lines by mixed newline characters", function()
      local actual = pod.splitLines("foo\r\nbar\rbazz\nhoge")
      local expected = { "foo\r\n", "bar\r", "bazz\n", "hoge" }
      assert.are.same(expected, actual)
    end)
  end)

  describe("splitParagraph function", function()
    it("splits paragraphs by empty line", function()
      local actual = pod.splitParagraphs("foo\n\nbar\n\nbazz")
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "para",
          value = unindent([[
          bar

          ]]),
          startIndex = 6,
          endIndex = 10,
        },
        {
          kind = "para",
          value = "bazz",
          startIndex = 11,
          endIndex = 14,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by over-back block", function()
      local actual = pod.splitParagraphs(unindent([[
        foo

        =over

        =item bar

        =item bazz

        =back

        hoge]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "list",
          value = unindent([[
          =over

          =item bar

          =item bazz

          =back

          ]]),
          startIndex = 6,
          endIndex = 42,
        },
        {
          kind = "para",
          value = "hoge",
          startIndex = 43,
          endIndex = 46,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by nested over-back block", function()
      local actual = pod.splitParagraphs(unindent([[
        foo

        =over

        =item bar

        =over

        =item bazz

        =back

        =item hoge

        =back

        fuga]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          startIndex = 1,
          endIndex = 5,
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
          startIndex = 6,
          endIndex = 68,
        },
        {
          kind = "para",
          value = "fuga",
          startIndex = 69,
          endIndex = 72,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits paragraphs by begin-end block", function()
      local actual = pod.splitParagraphs(unindent([[
        foo

        =begin html

        <p>bar</p>

        =end html

        bar]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "html",
          value = unindent([[
          =begin html

          <p>bar</p>

          =end html

          ]]),
          startIndex = 6,
          endIndex = 41,
        },
        {
          kind = "para",
          value = "bar",
          startIndex = 42,
          endIndex = 44,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("does not split lines with no empty line", function()
      local actual = pod.splitParagraphs("foo\nbar\nbazz")
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo
          bar
          bazz]]),
          startIndex = 1,
          endIndex = 12,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("does not split lines with no empty line", function()
      local actual = pod.splitParagraphs(unindent([[
        foo

        =over

        =item bar

        =item bazz

        =back
        hoge]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          foo

          ]]),
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "list",
          value = unindent([[
          =over

          =item bar

          =item bazz

          =back
          hoge]]),
          startIndex = 6,
          endIndex = 45,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitItems function", function()
    it("split no items", function()
      local actual = pod.splitItems(unindent([[
        lorem ipsum
        dolor sit amet]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          lorem ipsum
          dolor sit amet]]),
          startIndex = 1,
          endIndex = 26,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split no items with list", function()
      local actual = pod.splitItems(unindent([[
        lorem ipsum

        =over
        =item hoge
        =item fuga
        =back

        dolor sit amet]]))
      local expected = {
        {
          kind = "para",
          value = unindent([[
          lorem ipsum

          ]]),
          startIndex = 1,
          endIndex = 13,
        },
        {
          kind = "list",
          value = unindent([[
          =over
          =item hoge
          =item fuga
          =back

          ]]),
          startIndex = 14,
          endIndex = 48,
        },
        {
          kind = "para",
          value = "dolor sit amet",
          startIndex = 49,
          endIndex = 62,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split items", function()
      local actual = pod.splitItems(unindent([[
        =item foo

        =item bar

        =item bazz]]))
      local expected = {
        {
          kind = "item",
          value = unindent([[
          =item foo

          ]]),
          startIndex = 1,
          endIndex = 11,
        },
        {
          kind = "item",
          value = unindent([[
          =item bar

          ]]),
          startIndex = 12,
          endIndex = 22,
        },
        {
          kind = "item",
          value = unindent([[
          =item bazz]]),
          startIndex = 23,
          endIndex = 32,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split items with nested list", function()
      local actual = pod.splitItems(unindent([[
        =item foo

        =over
        =item bar

        =item bazz
        =back

        =item hoge]]))
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
          startIndex = 1,
          endIndex = 46,
        },
        {
          kind = "item",
          value = "=item hoge",
          startIndex = 47,
          endIndex = 56,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)

  describe("splitItem function", function()
    it("split parts", function()
      local actual = pod.splitItem(unindent([[
        =item foo bar]]))
      local expected = {
        {
          kind = "itempart",
          value = "=item foo bar",
          startIndex = 1,
          endIndex = 13,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("splits parts with begin - end", function()
      local actual = pod.splitItem(unindent([[
        =item foo
        bar
        =over
        =item
        =back

        bazz]]))
      local expected = {
        {
          kind = "itempart",
          value = unindent([[
          =item foo
          bar
          ]]),
          startIndex = 1,
          endIndex = 14,
        },
        {
          kind = "list",
          value = unindent([[
          =over
          =item
          =back

          ]]),
          startIndex = 15,
          endIndex = 33,
        },
        {
          kind = "itempart",
          value = "bazz",
          startIndex = 34,
          endIndex = 37,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitTokens function", function()
    it("split tokens without cmd", function()
      local actual = pod.splitTokens(unindent([[
        foo bar]]))
      local expected = {
        {
          kind = "text",
          value = "foo bar",
          startIndex = 1,
          endIndex = 7,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split tokens with cmd", function()
      local actual = pod.splitTokens(unindent([[
        foo bar C<hoge> huga]]))
      local expected = {
        {
          kind = "text",
          value = "foo bar ",
          startIndex = 1,
          endIndex = 8,
        },
        {
          kind = "C",
          value = "C<hoge>",
          startIndex = 9,
          endIndex = 15,
        },
        {
          kind = "text",
          value = " huga",
          startIndex = 16,
          endIndex = 20,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
end)
