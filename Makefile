CFLAGS  := -std=c99 -Wall -O2 -D_REENTRANT
LIBS    := -lpthread -lm -lcrypto -lssl

TARGET  := $(shell uname -s | tr '[A-Z]' '[a-z]' 2>/dev/null || echo unknown)
ARCH    := $(shell uname -m 2>/dev/null || echo unknown)

ifeq ($(TARGET), sunos)
	CFLAGS += -D_PTHREADS -D_POSIX_C_SOURCE=200112L
	LIBS   += -lsocket -lrt
else ifeq ($(TARGET), darwin)
	# Per https://luajit.org/install.html: If MACOSX_DEPLOYMENT_TARGET
	# is not set then it's forced to 10.4, which breaks compile on Mojave.
	export MACOSX_DEPLOYMENT_TARGET = $(shell sw_vers -productVersion)
	ifeq ($(ARCH), x86_64)
		LDFLAGS += -pagezero_size 10000 -image_base 100000000
	endif
	OPENSSL := $(shell brew --prefix openssl@3 2>/dev/null || echo /usr/local/opt/openssl)
	LIBS += -L$(OPENSSL)/lib
	CFLAGS += -I/usr/local/include -I$(OPENSSL)/include
else ifeq ($(TARGET), linux)
        CFLAGS  += -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE
	LIBS    += -ldl
	LDFLAGS += -Wl,-E
else ifeq ($(TARGET), freebsd)
	CFLAGS  += -D_DECLARE_C99_LDBL_MATH
	LDFLAGS += -Wl,-E
endif

SRC  := wrk.c affinity.c net.c ssl.c aprintf.c stats.c script.c units.c \
		ae.c zmalloc.c http_parser.c tinymt64.c hdr_histogram.c
BIN  := wrk

# Build with sanitizers. Run `make clean` when toggling SANITIZE.
#   make SANITIZE=1           # address,undefined
#   make SANITIZE=undefined   # UBSan only (use where ASan can't init)
# NOTE: ASan cannot initialize on recent macOS (the instrumented malloc
# zone hangs its shadow-memory setup). Use SANITIZE=undefined there.
LUAJIT_BUILD_OPTS :=
ifdef SANITIZE
	ifeq ($(SANITIZE),1)
		SAN_LIST := address,undefined
	else
		SAN_LIST := $(SANITIZE)
	endif
	CFLAGS  += -fsanitize=$(SAN_LIST) -fno-omit-frame-pointer -fno-sanitize-recover=all -g -O1
	LDFLAGS += -fsanitize=$(SAN_LIST)
	# ASan and LuaJIT's allocator collide only on x86_64, where LuaJIT wants
	# the low 2GB that ASan reserves for shadow memory. System malloc avoids
	# it. Do NOT do this on ARM64: sysmalloc breaks LuaJIT's GC arena there.
	ifneq (,$(findstring address,$(SAN_LIST)))
		ifeq ($(ARCH),x86_64)
			LUAJIT_BUILD_OPTS += XCFLAGS=-DLUAJIT_USE_SYSMALLOC
		endif
	endif
endif

# Static analysis. Override CPPCHECK to point at a specific binary.
CPPCHECK       ?= cppcheck
CPPCHECK_FLAGS := --enable=warning,performance,portability,style \
		--suppressions-list=.cppcheck-suppressions \
		--std=c11 --language=c --error-exitcode=1 -q -I src

ODIR := obj
OBJ  := $(patsubst %.c,$(ODIR)/%.o,$(SRC)) $(ODIR)/bytecode.o

LDIR     = deps/luajit/src
LIBS    := -lluajit $(LIBS)
CFLAGS  += -I$(LDIR)
LDFLAGS += -L$(LDIR)

all: $(BIN)

clean:
	$(RM) $(BIN) obj/*
	@$(MAKE) -C deps/luajit clean

$(BIN): $(OBJ)
	@echo LINK $(BIN)
	@$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

$(OBJ): config.h Makefile $(LDIR)/libluajit.a | $(ODIR)

$(ODIR):
	@mkdir -p $@

$(ODIR)/bytecode.o: src/wrk.lua
	@echo LUAJIT $<
	@$(SHELL) -c 'cd $(LDIR) && ./luajit -b $(CURDIR)/$< $(CURDIR)/$@'

$(ODIR)/%.o : %.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<

$(LDIR)/libluajit.a:
	@echo Building LuaJIT...
	@$(MAKE) -C $(LDIR) BUILDMODE=static $(LUAJIT_BUILD_OPTS)

cppcheck: ## Run static analysis over src (clean == no output)
	@$(CPPCHECK) $(CPPCHECK_FLAGS) src

# The CI gate. `make ci` is the whole thing and is what to run locally.
#
# Cloud Build calls the two halves separately, on different base images, so
# that the analyzer version is not tied to the build toolchain. See
# cloudbuild.yaml. Keep them runnable independently.
#
# ci-matrix builds and tests once per compiler, which is the coverage the old
# Travis matrix gave us. Each pass starts from clean so LuaJIT is rebuilt with
# the matching compiler. That means it deletes existing build output. On macOS
# gcc is an alias for clang, so override the list there:
#   make ci CI_COMPILERS=clang
CI_COMPILERS ?= gcc clang

ci: ## Run the full gate: static analysis, then build and test per compiler
	@$(MAKE) cppcheck
	@$(MAKE) ci-matrix

# `set -e` matters here. Without it the loop exits with the status of its last
# iteration, so a failure under gcc would be masked by a pass under clang.
ci-matrix: ## Build and test under each compiler in CI_COMPILERS
	@set -e; for cc in $(CI_COMPILERS); do \
		echo "==> CI with $$cc"; \
		$(MAKE) clean; \
		$(MAKE) CC=$$cc all test; \
	done

# Each suite appends itself here as it lands, so ci-matrix and cloudbuild.yaml
# never need to change to pick one up.
test: test-affinity test-thread-start test-cli-help ## Run all tests

test-affinity: | $(ODIR) ## Test CPU affinity list parsing
	@$(CC) $(CFLAGS) -Isrc -o $(ODIR)/affinity_test \
		tests/affinity_test.c src/affinity.c -lpthread
	@$(ODIR)/affinity_test

test-thread-start: $(BIN) ## Test synchronized worker benchmark start
	@python3 tests/thread_start_timing_test.py ./$(BIN)

test-cli-help: $(BIN) ## Test CLI help flags
	@python3 tests/cli_help_test.py ./$(BIN)

.PHONY: all ci ci-matrix clean cppcheck test test-affinity test-thread-start \
	test-cli-help
.SUFFIXES:
.SUFFIXES: .c .o .lua

vpath %.c   src
vpath %.h   src
vpath %.lua scripts

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
