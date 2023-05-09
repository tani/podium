local pod = require './pod'

describe("POD Parser", function()

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
          offset = 1,
          limit = 5,
        },
        {
          kind = "para",
          lines = { "bar\n", "\n" },
          offset = 6,
          limit = 10,
        },
        {
          kind = "para",
          lines = { "bazz" },
          offset = 11,
          limit = 14,
        },
      }
      assert.are.same(expected, actual)
    end)
  it("splits paragraphs by over-back block", function()
    local actual = pod.splitParagraphs[[
foo

=over

=item bar

=item bazz

=back

hoge]]
    local expected = {
      {
        kind = "para",
        lines = { "foo\n", "\n" },
        offset = 1,
        limit = 5,
      },
      {
        kind = "list",
        lines = {
          "=over\n", "\n",
          "=item bar\n", "\n",
          "=item bazz\n", "\n",
          "=back\n", "\n",
        },
        offset = 6,
        limit = 41,
      },
      {
        kind = "para",
        lines = { "hoge" },
        offset = 42,
        limit = 45,
      },
    }
  end)
  end)
end)
