ERL_ROOT ?= $(HOME)/.local/share/mise/installs/erlang/latest
REBAR ?= $(HOME)/.local/bin/rebar3
export PATH := $(ERL_ROOT)/bin:$(HOME)/.local/bin:$(PATH)

.PHONY: compile test eunit run dialyzer sast

compile:
	$(REBAR) compile

test: eunit

eunit: compile
	$(REBAR) eunit

dialyzer: compile
	$(REBAR) dialyzer

# Primitive Erlang Security Tool — this app's .erl only (not _build deps).
sast:
	$(CURDIR)/tools/pest/pest.erl -e -r src

run: compile
	erl -pa $(CURDIR)/_build/default/lib/*/ebin -config $(CURDIR)/config/sys -noshell -s carolina main
