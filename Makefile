TOOLCHAIN := $(CURDIR)/.tools/agda/bin
export PATH := $(TOOLCHAIN):$(PATH)
AGDA ?= $(if $(wildcard $(TOOLCHAIN)/agda),$(TOOLCHAIN)/agda,agda)
PYTHON ?= $(if $(wildcard $(TOOLCHAIN)/python3),$(TOOLCHAIN)/python3,python3)
PREFIX ?= /usr/local
SOURCES := $(shell find src -name '*.agda')

.PHONY: all bootstrap verify test install clean
all: json2dir

bootstrap:
	nix build path:.\#toolchain --out-link .tools/agda

verify:
	$(AGDA) --no-libraries -i src src/Json2dir/Proofs.agda
	$(AGDA) --no-libraries -i src src/Main.agda

json2dir: $(SOURCES)
	$(AGDA) --no-libraries -i src src/Json2dir/Proofs.agda
	$(AGDA) --no-libraries -i src --compile --compile-dir=build --ghc-flag=-O2 src/Main.agda
	cp build/Main $@

test: json2dir
	$(PYTHON) tests/test_cli.py ./json2dir

install: json2dir
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 json2dir $(DESTDIR)$(PREFIX)/bin/json2dir

clean:
	rm -rf build json2dir
	find src -name '*.agdai' -delete
