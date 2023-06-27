.PHONY: format test serve

format:
	stylua **/*.lua

test:
	busted -m lua/?.lua

serve:
	deno run -A deno/app.ts