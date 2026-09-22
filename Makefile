ERL_ROOT ?= $(HOME)/.local/share/mise/installs/erlang/latest
GITLEAKS_HOME ?= $(HOME)/.local/share/mise/installs/gitleaks/8.30.1
export PATH := $(ERL_ROOT)/bin:$(HOME)/.local/bin:$(GITLEAKS_HOME):/usr/local/bin:$(PATH)

REBAR ?= rebar3
GITLEAKS ?= gitleaks

.PHONY: compile test eunit run dialyzer sast audit lint secrets check hooks xref

compile:
	$(REBAR) compile

test: eunit

eunit: compile xref
	$(REBAR) eunit

xref: compile
	$(REBAR) xref

dialyzer: compile
	$(REBAR) dialyzer

# Primitive Erlang Security Tool — this app's .erl only (not _build deps).
sast:
	$(CURDIR)/tools/pest/pest.erl -e -r src

# Unset GITHUB_TOKEN so a Gitea job token is not sent to GitHub's advisory API.
audit:
	env -u GITHUB_TOKEN $(REBAR) audit

lint:
	$(REBAR) lint

# Git history (CI / --all-files) plus staged diff so a commit cannot sneak a secret.
secrets:
	$(GITLEAKS) detect --source . --verbose --redact
	@if git diff --cached --quiet; then :; else $(GITLEAKS) git --pre-commit --staged --verbose --redact; fi

check: dialyzer eunit sast audit secrets lint

hooks:
	pre-commit install
	git config core.hooksPath .githooks

run: compile
	$(CURDIR)/bin/server
