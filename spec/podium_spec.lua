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
    it("split simple indent block", function()
      local content = unindent([[
      =over 8

      hoge

      =back
      ]])
      local actual = pod.splitList(content)
      local expected = {
        {
          kind = "over",
          lines = {
            "=over 8\n", "\n",
          },
          startIndex = 1,
          endIndex = 9,
        },
        {
          kind = "items",
          lines = {
            "hoge\n", "\n",
          },
          startIndex = 10,
          endIndex = 15,
        },
        {
          kind = "back",
          lines = {
            "=back\n",
          },
          startIndex = 16,
          endIndex = 21,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split nested indent block", function()
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
          kind = "over",
          lines = {
            "=over 8\n", "\n",
          },
          startIndex = 1,
          endIndex = 9,
        },
        {
          kind = "items",
          lines = {
            "hoge\n", "\n",
            "=over 4\n", "\n",
            "=item fuga\n", "\n",
            "=back\n", "\n",
          },
          startIndex = 10,
          endIndex = 43,
        },
        {
          kind = "back",
          lines = {
            "=back\n",
          },
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
          lines = { "foo\n", "\n" },
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "para",
          lines = { "bar\n", "\n" },
          startIndex = 6,
          endIndex = 10,
        },
        {
          kind = "para",
          lines = { "bazz" },
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
          lines = { "foo\n", "\n" },
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "list",
          lines = {
            "=over\n",
            "\n",
            "=item bar\n",
            "\n",
            "=item bazz\n",
            "\n",
            "=back\n",
            "\n",
          },
          startIndex = 6,
          endIndex = 42,
        },
        {
          kind = "para",
          lines = { "hoge" },
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
          lines = { "foo\n", "\n" },
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "list",
          lines = {
            "=over\n",
            "\n",
            "=item bar\n",
            "\n",
            "=over\n",
            "\n",
            "=item bazz\n",
            "\n",
            "=back\n",
            "\n",
            "=item hoge\n",
            "\n",
            "=back\n",
            "\n",
          },
          startIndex = 6,
          endIndex = 68,
        },
        {
          kind = "para",
          lines = { "fuga" },
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
          lines = { "foo\n", "\n" },
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "html",
          lines = {
            "=begin html\n",
            "\n",
            "<p>bar</p>\n",
            "\n",
            "=end html\n",
            "\n",
          },
          startIndex = 6,
          endIndex = 41,
        },
        {
          kind = "para",
          lines = { "bar" },
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
          lines = { "foo\n", "bar\n", "bazz" },
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
          lines = { "foo\n", "\n" },
          startIndex = 1,
          endIndex = 5,
        },
        {
          kind = "list",
          lines = {
            "=over\n",
            "\n",
            "=item bar\n",
            "\n",
            "=item bazz\n",
            "\n",
            "=back\n",
            "hoge",
          },
          startIndex = 6,
          endIndex = 45,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
  describe("splitItems function", function()
    it("split items", function()
      local actual = pod.splitItems(unindent([[
        =over
        =item foo

        =item bar

        =item bazz
        =back]]))
      local expected = {
        {
          kind = "over",
          lines = {
            "=over\n",
          },
          startIndex = 1,
          endIndex = 6,
        },
        {
          kind = "item",
          lines = {
            "=item foo\n",
            "\n",
          },
          startIndex = 7,
          endIndex = 17,
        },
        {
          kind = "item",
          lines = {
            "=item bar\n",
            "\n",
          },
          startIndex = 18,
          endIndex = 28,
        },
        {
          kind = "item",
          lines = {
            "=item bazz\n",
          },
          startIndex = 29,
          endIndex = 39,
        },
        {
          kind = "back",
          lines = {
            "=back",
          },
          startIndex = 40,
          endIndex = 44,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split items with nested list", function()
      local actual = pod.splitItems(unindent([[
        =over
        =item foo

        =over
        =item bar

        =item bazz
        =back

        =item hoge
        =back]]))
      local expected = {
        {
          kind = "over",
          lines = {
            "=over\n",
          },
          startIndex = 1,
          endIndex = 6,
        },
        {
          kind = "item",
          lines = {
            "=item foo\n",
            "\n",
            "=over\n",
            "=item bar\n",
            "\n",
            "=item bazz\n",
            "=back\n",
            "\n",
          },
          startIndex = 7,
          endIndex = 52,
        },
        {
          kind = "item",
          lines = {
            "=item hoge\n",
          },
          startIndex = 53,
          endIndex = 63,
        },
        {
          kind = "back",
          lines = {
            "=back",
          },
          startIndex = 64,
          endIndex = 68,
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
          lines = {
            "=item foo bar",
          },
          startIndex = 1,
          endIndex = 13,
        },
      }
      assert.are.same(expected, actual)
    end)
    it("split parts with begin - end", function()
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
          lines = {
            "=item foo\n",
            "bar\n",
          },
          startIndex = 1,
          endIndex = 14,
        },
        {
          kind = "list",
          lines = {
            "=over\n",
            "=item\n",
            "=back\n",
            "\n",
          },
          startIndex = 15,
          endIndex = 33,
        },
        {
          kind = "itempart",
          lines = {
            "bazz",
          },
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
          lines = {
            "foo bar",
          },
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
          lines = {
            "foo bar ",
          },
          startIndex = 1,
          endIndex = 8,
        },
        {
          kind = "C",
          lines = {
            "C<hoge>",
          },
          startIndex = 9,
          endIndex = 15,
        },
        {
          kind = "text",
          lines = {
            " huga",
          },
          startIndex = 16,
          endIndex = 20,
        },
      }
      assert.are.same(expected, actual)
    end)
  end)
end)
