ERL_ROOT ?= $(HOME)/.local/share/mise/installs/erlang/latest
REBAR ?= $(HOME)/.local/bin/rebar3
export PATH := $(ERL_ROOT)/bin:$(HOME)/.local/bin:$(PATH)

.PHONY: compile test run dialyzer

compile:
	$(REBAR) compile

test: compile
	$(REBAR) eunit

dialyzer: compile
	$(REBAR) dialyzer

run: compile
	erl -pa $(CURDIR)/_build/default/lib/*/ebin -config $(CURDIR)/config/sys -noshell -s carolina main
