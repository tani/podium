.PHONY: format test serve

format:
	stylua **/*.lua

check:
	lua-language-server --check lua/podium.lua

test:
	busted -m lua/?.lua

serve:
	deno run -A deno/app.ts
