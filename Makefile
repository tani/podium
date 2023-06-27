.PHONY: fmt test

fmt:
	stylua -g lua/*.lua

test:
	busted -m lua/?.lua