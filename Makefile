PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
BUILD ?= build

# Version and release metadata
VERSION ?= $(shell awk '/^## Version/{getline; print; exit}' README.md)
GIT_COMMIT := $(shell git rev-parse --short=12 HEAD 2>/dev/null)
GIT_TAG := $(shell git describe --tags --exact-match HEAD 2>/dev/null)
DIST_VERSION ?= $(if $(GIT_TAG),$(patsubst v%,%,$(GIT_TAG)),$(VERSION)-g$(GIT_COMMIT))
DIST_NAME := git2html-$(DIST_VERSION)
UNAME_S := $(shell uname -s | tr '[:upper:]' '[:lower:]')
UNAME_M := $(shell uname -m)
DIST_BIN_NAME := $(DIST_NAME)-$(UNAME_S)-$(UNAME_M)
DIST_DIR := $(BUILD)/dist
DIST_STAGE := $(BUILD)/dist-stage
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct HEAD 2>/dev/null)
ifeq ($(SOURCE_DATE_EPOCH),)
  SOURCE_DATE_EPOCH := $(shell date +%s)
endif

# Tool variables for distribution
TAR ?= tar
XZ ?= xz
SHA256SUM ?= sha256sum

# Deterministic archive options (GNU tar; xz runs single-threaded so output is stable): sorted names, commit timestamp,
# numeric root ownership, and normalized permissions (no setuid or setgid bits).
REPRO_TAR = $(TAR) --sort=name --format=gnu --mtime=@$(SOURCE_DATE_EPOCH) \
            --owner=0 --group=0 --numeric-owner --mode='u+rwX,go+rX,go-w,a-s'

define export-public-tree
	rm -rf $(1)
	mkdir -p $(1)
	git archive --format=tar HEAD | (cd $(1) && $(TAR) --no-same-owner -xf -)
	rm -rf $(1)/doc/archive
	printf -- '---\nproject: git2html\nstatus: Archive\ndate: %s\n---\n\n# Completed Archive\n' \
		"$$(git log -1 --format=%cs HEAD 2>/dev/null || date +%Y-%m-%d)" > $(1)/doc/tasks/completed.tm.md
endef

ifeq ($(origin CC),default)
  CC = gcc
endif
LUA ?= lua
SCDOC ?= scdoc
MIN_SCDOC_VERSION := 1.11.5
# The embedded binary is linked statically against musl (glibc warns about
# dlopen in static executables). Use musl-gcc when available (e.g. on glibc
# distros with musl-tools), falling back to CC (e.g. on Alpine Linux where
# gcc targets musl natively).
ifeq ($(origin STATIC_CC),undefined)
  STATIC_CC := $(shell command -v musl-gcc >/dev/null 2>&1 && echo musl-gcc || echo $(CC))
endif

LUA_SRC = vendor/lua
LPEG_SRC = vendor/lpeg
OBJ = $(BUILD)/obj
MAN_SRC = doc/man/git2html.1.scd
MAN = doc/man/git2html.1

LUA_C = $(wildcard $(LUA_SRC)/*.c)
LUA_O = $(patsubst $(LUA_SRC)/%.c,$(OBJ)/%.o,$(LUA_C))
LPEG_C = $(LPEG_SRC)/lpvm.c $(LPEG_SRC)/lpcap.c $(LPEG_SRC)/lptree.c \
	$(LPEG_SRC)/lpcode.c $(LPEG_SRC)/lpprint.c $(LPEG_SRC)/lpcset.c
LPEG_O = $(patsubst $(LPEG_SRC)/%.c,$(OBJ)/%.o,$(LPEG_C))

all: check-user-deps $(BUILD)/git2html
build: all

# The man page date is pinned to the source file's last commit time (falling
# back to SOURCE_DATE_EPOCH or its mtime outside a git checkout) so rebuilding
# doesn't dirty the committed doc/man/git2html.1.
MAN_EPOCH = $(if $(SOURCE_DATE_EPOCH),$(SOURCE_DATE_EPOCH),$(shell git log -1 --format=%ct -- $(MAN_SRC) 2>/dev/null | grep . || stat -c %Y $(MAN_SRC)))

$(MAN):
	@if [ ! -f "$@" ]; then \
		if command -v $(SCDOC) >/dev/null 2>&1; then \
			scdoc_ver=$$($(SCDOC) -v 2>/dev/null | awk '{print $$2}'); \
			if [ -n "$$scdoc_ver" ] && ! $(LUA) -e 'local function p(s) local a,b,c=s:match("(%d+)%.(%d+)%.?(%d*)"); return {tonumber(a) or 0,tonumber(b) or 0,tonumber(c) or 0} end; local function ge(x,y) for i=1,3 do if x[i]>y[i] then return 0 elseif x[i]<y[i] then return 1 end end return 0 end; os.exit(ge(p("'$$scdoc_ver'"), p("$(MIN_SCDOC_VERSION)")))' 2>/dev/null; then \
				echo "ERROR: $@ is missing and $(SCDOC) is too old ($$scdoc_ver found, >= $(MIN_SCDOC_VERSION) required)." >&2; \
				echo "Please install $(SCDOC) >= $(MIN_SCDOC_VERSION) or restore $@ from git." >&2; \
				exit 1; \
			fi; \
			mkdir -p $(@D); \
			SOURCE_DATE_EPOCH=$(MAN_EPOCH) $(SCDOC) < $(MAN_SRC) > $@.tmp && mv $@.tmp $@; \
		else \
			echo "ERROR: $@ is missing and $(SCDOC) is not installed to generate it." >&2; \
			echo "Please install $(SCDOC) or restore $@ from git." >&2; \
			exit 1; \
		fi; \
	fi

man: $(MAN_SRC)
	@command -v $(SCDOC) >/dev/null 2>&1 || { echo "ERROR: $(SCDOC) is required to build man pages." >&2; exit 1; }
	@scdoc_ver=$$($(SCDOC) -v 2>/dev/null | awk '{print $$2}'); \
	if [ -n "$$scdoc_ver" ] && ! $(LUA) -e 'local function p(s) local a,b,c=s:match("(%d+)%.(%d+)%.?(%d*)"); return {tonumber(a) or 0,tonumber(b) or 0,tonumber(c) or 0} end; local function ge(x,y) for i=1,3 do if x[i]>y[i] then return 0 elseif x[i]<y[i] then return 1 end end return 0 end; os.exit(ge(p("'$$scdoc_ver'"), p("$(MIN_SCDOC_VERSION)")))' 2>/dev/null; then \
		echo "ERROR: $(SCDOC) >= $(MIN_SCDOC_VERSION) is required to build man pages (found $$scdoc_ver)." >&2; \
		exit 1; \
	fi
	mkdir -p $(@D)
	SOURCE_DATE_EPOCH=$(MAN_EPOCH) $(SCDOC) < $(MAN_SRC) > $(MAN).tmp && mv $(MAN).tmp $(MAN)
	@echo "Generated $(MAN)"

# The static binary: a Lua 5.4 interpreter and lpeg (both vendored as C
# source under vendor/), plus src/git2html.lua, src/git_utils.lua, every vendored
# Lua module and the bundled themes, all compiled into one self-contained
# executable with no run-time dependency on the system's Lua install --
# see src/bundle_main.c for how it's assembled.
$(OBJ): | check-user-deps
	mkdir -p $(OBJ)

$(OBJ)/%.o: $(LUA_SRC)/%.c | $(OBJ)
	$(STATIC_CC) -std=gnu99 -O2 -DLUA_USE_LINUX -I$(LUA_SRC) -c $< -o $@

$(OBJ)/%.o: $(LPEG_SRC)/%.c | $(OBJ)
	$(STATIC_CC) -std=c99 -O2 -DNDEBUG -I$(LUA_SRC) -c $< -o $@

$(BUILD)/bundle_data.c: tools/gen_bundle.lua src/git2html.lua src/git_utils.lua \
		$(shell find vendor -name '*.lua') $(wildcard themes/*.css) | $(OBJ)
	$(LUA) tools/gen_bundle.lua

$(OBJ)/bundle_data.o: $(BUILD)/bundle_data.c src/bundle_data.h | $(OBJ)
	$(STATIC_CC) -std=gnu99 -O1 -I$(LUA_SRC) -Isrc -I$(BUILD) -c $< -o $@

$(OBJ)/bundle_main.o: src/bundle_main.c src/bundle_data.h | $(OBJ)
	$(STATIC_CC) -std=gnu99 -O2 -Wall -Wextra -I$(LUA_SRC) -Isrc -I$(BUILD) -c $< -o $@

$(BUILD)/git2html: $(OBJ)/bundle_main.o $(OBJ)/bundle_data.o $(LPEG_O) $(LUA_O)
	$(STATIC_CC) -static -o $@ $^ -lm

# lpeg built as a shared module against whatever Lua is actually on PATH,
# used only when running src/git2html.lua directly as a script (e.g. by `make
# test`) rather than via the compiled binary above. Built fresh from source
# every time rather than committed, since a prebuilt lpeg.so is only valid
# for the exact Lua ABI it was compiled against.
LUA_VER := $(shell command -v $(LUA) >/dev/null 2>&1 && $(LUA) -e 'print(_VERSION:match("%d+%.%d+"))' 2>/dev/null)
LUA_PKG_CANDIDATES := lua$(LUA_VER) lua-$(LUA_VER) lua$(subst .,,$(LUA_VER)) lua
LUA_PKG := $(shell command -v pkg-config >/dev/null 2>&1 && for p in $(LUA_PKG_CANDIDATES); do pkg-config --exists $$p 2>/dev/null && echo $$p && break; done)
LUA_CFLAGS := $(shell pkg-config --cflags $(LUA_PKG) 2>/dev/null)
LUA_LIBS := $(shell pkg-config --libs $(LUA_PKG) 2>/dev/null)

check-user-deps:
	@err=0; \
	is_goal=0; \
	case " $(MAKECMDGOALS) " in *" check-user-deps "*|*" check-build-deps "*) is_goal=1 ;; esac; \
	if [ $$is_goal -eq 1 ]; then echo "Checking user dependencies:"; fi; \
	if p=$$(command -v "$(STATIC_CC)" 2>/dev/null); then \
		if [ $$is_goal -eq 1 ]; then echo "  [OK] C compiler ($(STATIC_CC)): $$p"; fi; \
	else \
		echo "  [FAIL] C compiler ($(STATIC_CC)): not found" >&2; \
		err=1; \
	fi; \
	if p=$$(command -v "$(LUA)" 2>/dev/null); then \
		if [ $$is_goal -eq 1 ]; then echo "  [OK] Lua interpreter ($(LUA)): $$p"; fi; \
	else \
		echo "  [FAIL] Lua interpreter ($(LUA)): not found" >&2; \
		err=1; \
	fi; \
	if [ $$err -ne 0 ]; then \
		echo "ERROR: Missing required user dependencies to build git2html." >&2; \
		exit $$err; \
	fi; \
	if [ $$is_goal -eq 1 ]; then echo "All user dependencies satisfied."; fi

check-build-deps: check-user-deps

check-dev-deps: check-user-deps
	@err=0; \
	is_goal=0; \
	case " $(MAKECMDGOALS) " in *" check-dev-deps "*|*" check-test-deps "*) is_goal=1 ;; esac; \
	if [ $$is_goal -eq 1 ]; then echo "Checking developer dependencies:"; fi; \
	if p=$$(command -v git 2>/dev/null); then \
		if [ $$is_goal -eq 1 ]; then echo "  [OK] git: $$p"; fi; \
	else \
		echo "  [FAIL] git (version control): not found" >&2; \
		err=1; \
	fi; \
	if p=$$(command -v pkg-config 2>/dev/null); then \
		if [ $$is_goal -eq 1 ]; then echo "  [OK] pkg-config: $$p"; fi; \
	else \
		echo "  [FAIL] pkg-config (library helper): not found" >&2; \
		err=1; \
	fi; \
	if p=$$(command -v "$(CC)" 2>/dev/null); then \
		if [ $$is_goal -eq 1 ]; then echo "  [OK] C compiler for shared modules ($(CC)): $$p"; fi; \
	else \
		echo "  [FAIL] C compiler for shared modules ($(CC)): not found" >&2; \
		err=1; \
	fi; \
	if [ -z "$(LUA_PKG)" ]; then \
		echo "  [FAIL] Lua $(LUA_VER) development package: not found" >&2; \
		echo "         pkg-config could not find any of: $(LUA_PKG_CANDIDATES)" >&2; \
		echo "         $(BUILD)/lpeg.so must be compiled against Lua $(LUA_VER) headers to match $(LUA) ($$($(LUA) -v 2>&1))." >&2; \
		echo "         Please install the development package for Lua $(LUA_VER) (e.g. 'lua' or 'lua$(LUA_VER)')." >&2; \
		err=1; \
	else \
		pkg_ver=$$(pkg-config --modversion $(LUA_PKG) 2>/dev/null | grep -o '^[0-9]\+\.[0-9]\+'); \
		if [ -n "$$pkg_ver" ] && [ "$$pkg_ver" != "$(LUA_VER)" ]; then \
			echo "  [FAIL] Lua version mismatch between $(LUA) and $(LUA_PKG)" >&2; \
			echo "         $(LUA) binary version:        $(LUA_VER) ($$($(LUA) -v 2>&1))" >&2; \
			echo "         $(LUA_PKG) pkg-config version: $$pkg_ver" >&2; \
			echo "         Compiling $(BUILD)/lpeg.so against a mismatched Lua ABI causes segmentation faults." >&2; \
			echo "         Please install the matching Lua $(LUA_VER) development package." >&2; \
			err=1; \
		elif [ $$is_goal -eq 1 ]; then \
			echo "  [OK] Lua $(LUA_VER) development package ($(LUA_PKG)): $$pkg_ver"; \
		fi; \
	fi; \
	if [ $$err -ne 0 ]; then \
		echo "ERROR: Missing required developer dependencies." >&2; \
		exit $$err; \
	fi; \
	if [ $$is_goal -eq 1 ]; then \
		echo "Optional developer dependencies:"; \
		if p=$$(command -v $(SCDOC) 2>/dev/null); then \
			scdoc_ver=$$($$p -v 2>/dev/null | awk '{print $$2}'); \
			if [ -n "$$scdoc_ver" ] && ! $(LUA) -e 'local function p(s) local a,b,c=s:match("(%d+)%.(%d+)%.?(%d*)"); return {tonumber(a) or 0,tonumber(b) or 0,tonumber(c) or 0} end; local function ge(x,y) for i=1,3 do if x[i]>y[i] then return 0 elseif x[i]<y[i] then return 1 end end return 0 end; os.exit(ge(p("'$$scdoc_ver'"), p("$(MIN_SCDOC_VERSION)")))' 2>/dev/null; then \
				echo "  [SKIP] scdoc (man page generator): $$p ($$scdoc_ver found, >= $(MIN_SCDOC_VERSION) required for 'make man' and tests)"; \
			else \
				echo "  [OK] scdoc (man page generator): $$p ($$scdoc_ver)"; \
			fi; \
		else \
			echo "  [SKIP] scdoc: not found (optional; needed for 'make man' and man page tests)"; \
		fi; \
		if p=$$(command -v webveld-validate 2>/dev/null); then \
			echo "  [OK] webveld-validate (WebVeld validator): $$p"; \
		else \
			echo "  [SKIP] webveld-validate: not found (optional; needed for WebVeld tests)"; \
		fi; \
		echo "All required developer dependencies satisfied."; \
	fi

check-test-deps: check-dev-deps

$(BUILD)/lpeg.so: $(LPEG_C) | check-dev-deps $(OBJ)
	$(CC) -std=c99 -O2 -DNDEBUG -fPIC $(LUA_CFLAGS) -shared -o $@ $(LPEG_C) $(LUA_LIBS)
	@$(LUA) -e 'package.cpath="./$(BUILD)/?.so;" .. package.cpath; local ok, err = pcall(require, "lpeg"); if not ok then io.stderr:write("ERROR: Built $(BUILD)/lpeg.so failed to load in $(LUA):\n  " .. tostring(err) .. "\n"); os.exit(1) end'

test: $(BUILD)/git2html check-dev-deps $(BUILD)/lpeg.so
	@GIT_CONFIG_GLOBAL=/dev/null \
	GIT_CONFIG_SYSTEM=/dev/null \
	GIT_AUTHOR_NAME="$${GIT_AUTHOR_NAME:-Test}" \
	GIT_AUTHOR_EMAIL="$${GIT_AUTHOR_EMAIL:-test@example.com}" \
	GIT_COMMITTER_NAME="$${GIT_COMMITTER_NAME:-Test}" \
	GIT_COMMITTER_EMAIL="$${GIT_COMMITTER_EMAIL:-test@example.com}" \
	GIT2HTML_BIN="$(CURDIR)/$(BUILD)/git2html" \
	SCDOC="$(SCDOC)" \
	$(LUA) test/runner.lua

clean:
	rm -rf $(BUILD)

dist:
	@test -n "$(GIT_COMMIT)" || { echo "make dist must run in a git checkout" >&2; exit 1; }
	@git diff --quiet HEAD -- || echo "note: uncommitted changes are not included; dist is built from HEAD ($(GIT_COMMIT))"
	@command -v $(TAR) >/dev/null 2>&1 || { echo "ERROR: $(TAR) is required for make dist." >&2; exit 1; }
	@command -v $(XZ) >/dev/null 2>&1 || { echo "ERROR: $(XZ) is required for make dist." >&2; exit 1; }
	@command -v $(SHA256SUM) >/dev/null 2>&1 || { echo "ERROR: $(SHA256SUM) is required for make dist." >&2; exit 1; }
	rm -rf $(DIST_DIR) $(DIST_STAGE)
	mkdir -p $(DIST_DIR) $(DIST_STAGE)
	$(call export-public-tree,$(DIST_STAGE)/$(DIST_NAME))
	cd $(DIST_STAGE) && $(REPRO_TAR) -cf $(CURDIR)/$(DIST_DIR)/$(DIST_NAME).tar $(DIST_NAME)
	$(MAKE) -s -C $(DIST_STAGE)/$(DIST_NAME) install DESTDIR=$(CURDIR)/$(DIST_STAGE)/install-root PREFIX=$(PREFIX) SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) > /dev/null
	cd $(DIST_STAGE)/install-root && $(REPRO_TAR) -cf $(CURDIR)/$(DIST_DIR)/$(DIST_BIN_NAME).tar .
	cd $(DIST_DIR) && for t in *.tar; do $(XZ) -9 -T1 "$$t" || exit 1; done
	cd $(DIST_DIR) && $(SHA256SUM) *.tar.xz > SHA256SUMS
	rm -rf $(DIST_STAGE)
	@echo "Release tarballs for $(DIST_NAME) (commit $(GIT_COMMIT)) in $(DIST_DIR)/:"
	@cat $(DIST_DIR)/SHA256SUMS

install: all $(MAN)
	install -D -m 755 $(BUILD)/git2html $(DESTDIR)$(BINDIR)/git2html
	install -D -m 644 $(MAN) $(DESTDIR)$(MANDIR)/git2html.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/git2html
	rm -f $(DESTDIR)$(MANDIR)/git2html.1

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "User Targets:"
	@echo "  all               Build git2html binary and man page (default)"
	@echo "  build             Alias for all"
	@echo "  install           Install git2html binary and man page"
	@echo "  uninstall         Remove installed git2html binary and man page"
	@echo "  clean             Remove build artifacts and temporary files"
	@echo "  check-user-deps   Verify dependencies required to build and install"
	@echo ""
	@echo "Developer Targets:"
	@echo "  test              Run the test suite (requires developer dependencies)"
	@echo "  man               Regenerate man page from scdoc source"
	@echo "  dist              Build reproducible source and install tarballs in $(DIST_DIR)/"
	@echo "  check-dev-deps    Verify developer dependencies (git, pkg-config, lua headers, scdoc, webveld)"
	@echo "  help              Display this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX            Installation prefix (default: /usr/local)"
	@echo "  DESTDIR           Staging directory for installation (default: empty)"
	@echo "  CC                C compiler for shared modules (default: gcc)"
	@echo "  STATIC_CC         C compiler for static binary (default: musl-gcc or CC)"
	@echo "  LUA               Lua interpreter command (default: lua)"

.PHONY: all build check-user-deps check-build-deps check-dev-deps check-test-deps test man clean install uninstall dist help
