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
					offset = 1,
					limit = 5,
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
					offset = 6,
					limit = 42,
				},
				{
					kind = "para",
					lines = { "hoge" },
					offset = 43,
					limit = 46,
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
					offset = 1,
					limit = 5,
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
					offset = 6,
					limit = 68,
				},
				{
					kind = "para",
					lines = { "fuga" },
					offset = 69,
					limit = 72,
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
					offset = 1,
					limit = 5,
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
					offset = 6,
					limit = 41,
				},
				{
					kind = "para",
					lines = { "bar" },
					offset = 42,
					limit = 44,
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
					offset = 1,
					limit = 12,
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
					offset = 1,
					limit = 5,
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
					offset = 6,
					limit = 45,
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
					offset = 1,
					limit = 6,
				},
				{
					kind = "item",
					lines = {
						"=item foo\n",
						"\n",
					},
					offset = 7,
					limit = 17,
				},
				{
					kind = "item",
					lines = {
						"=item bar\n",
						"\n",
					},
					offset = 18,
					limit = 28,
				},
				{
					kind = "item",
					lines = {
						"=item bazz\n",
					},
					offset = 29,
					limit = 39,
				},
				{
					kind = "back",
					lines = {
						"=back",
					},
					offset = 40,
					limit = 44,
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
					offset = 1,
					limit = 6,
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
					offset = 7,
					limit = 52,
				},
				{
					kind = "item",
					lines = {
						"=item hoge\n",
					},
					offset = 53,
					limit = 63,
				},
				{
					kind = "back",
					lines = {
						"=back",
					},
					offset = 64,
					limit = 68,
				},
			}
			assert.are.same(expected, actual)
		end)
	end)

	describe("splitItemParts function", function()
		it("split parts", function()
			local actual = pod.splitItemParts(unindent([[
        =item foo bar]]))
			local expected = {
				{
					kind = "part",
					lines = {
						"=item foo bar",
					},
					offset = 1,
					limit = 13,
				},
			}
			assert.are.same(expected, actual)
		end)
		it("split parts with begin - end", function()
			local actual = pod.splitItemParts(unindent([[
        =item foo
        bar
        =over
        =item
        =back

        bazz]]))
			local expected = {
				{
					kind = "part",
					lines = {
						"=item foo\n",
						"bar\n",
					},
					offset = 1,
					limit = 14,
				},
				{
					kind = "list",
					lines = {
						"=over\n",
						"=item\n",
						"=back\n",
						"\n",
					},
					offset = 15,
					limit = 33,
				},
				{
					kind = "part",
					lines = {
						"bazz",
					},
					offset = 34,
					limit = 37,
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
					offset = 1,
					limit = 7,
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
					offset = 1,
					limit = 8,
				},
				{
					kind = "C",
					lines = {
						"C<hoge>",
					},
					offset = 9,
					limit = 15,
				},
				{
					kind = "text",
					lines = {
						" huga",
					},
					offset = 16,
					limit = 20,
				},
			}
			assert.are.same(expected, actual)
		end)
	end)
end)
