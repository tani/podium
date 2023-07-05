.PHONY: format test serve doc

format:
	stylua **/*.lua

doc:
	./lua/podium.lua vimdoc README.pod > doc/podium.txt

check:
	lua-language-server --check lua/podium.lua

test:
	busted -m lua/?.lua

serve:
	deno run -A deno/app.ts
