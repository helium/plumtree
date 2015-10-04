REBAR = $(shell pwd)/rebar
.PHONY: deps compile rel

DIALYZER_APPS = kernel stdlib erts sasl eunit syntax_tools compiler crypto
DEP_DIR="_build/lib"

all: compile

test: common_test

deps:
	$(REBAR) get-deps

clean:
	$(REBAR) clean

distclean: clean
	$(REBAR) delete-deps

common_test:
	$(REBAR) ct

compile: deps
	$(REBAR) compile

rel:
	$(REBAR) release

stage:
	$(REBAR) release -d

DIALYZER_APPS = kernel stdlib sasl erts ssl tools os_mon runtime_tools crypto inets \
	xmerl webtool eunit syntax_tools compiler mnesia public_key snmp

include tools.mk

typer:
	typer --annotate -I ../ --plt $(PLT) -r src
