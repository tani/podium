.PHONY: fmt test

fmt:
	stylua **/*.lua

test:
	busted -m lua/?.lua