SHELL = /bin/bash

ifneq ("$(wildcard .env)","")
	include .env
	export
endif

.DEFAULT_GOAL := init

## help: Display list of commands
.PHONY: help
help: Makefile
	@sed -n 's|^##||p' $< | column -t -s ':' | sort

## init: Bootstrap your application. e.g. fetch some data files, make some API calls, request user input etc...
.PHONY: init
init:
	@curl -q -sSL --max-time 10 "https://raw.githubusercontent.com/ViBiOh/scripts/master/bootstrap" | bash -s "git_hooks"
