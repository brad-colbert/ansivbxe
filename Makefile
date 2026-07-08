MADS      ?= mads
CA65      ?= ca65
LD65      ?= ld65
AR65      ?= ar65

PROJ_NAME   = ANSIVBXE
DISK_DIR    = disk

MADS_SRC    = $(PROJ_NAME).asm
MADS_DEPS   = atarios.equ atarihardware.equ VBXE.equ
MADS_XEX    = $(PROJ_NAME).XEX
MADS_ATR    = $(PROJ_NAME).ATR

CA65_SRC    = $(PROJ_NAME)_ca65.asm
CA65_DEPS   = atarios_ca65.inc atarihardware_ca65.inc VBXE_ca65.inc
CA65_MAIN_DEPS = $(CA65_DEPS) scroll_rgn.inc
CA65_OBJ    = $(PROJ_NAME)_ca65.o
CA65_XEX    = $(PROJ_NAME)_ca65.XEX
CA65_ATR    = $(PROJ_NAME)_ca65.ATR
CA65_CFG    ?= /usr/local/share/cc65/cfg/atari-asm-xex.cfg
START_ADDR  ?= 0x2800

VBXE_LIB_SRC = vbxe_lib.asm
VBXE_LIB_OBJ = vbxe_lib.o
VBXE_LIB     = vbxe_lib.lib

CL65      ?= cl65
SIM65     ?= sim65
BUILD_DIR   = build
SCROLL_TEST_SRC = test/sim65/scroll_test.s
SCROLL_TEST_BIN = $(BUILD_DIR)/scroll_test.bin

.PHONY: all disk ca65 ca65-disk mads mads-disk vbxe-lib clean test

all: mads ca65

# Host-side unit test for the scrolling-region primitives. scroll_rgn.inc touches no
# Atari or VBXE hardware, so the same source the XEX uses runs under cc65's 6502
# simulator. Exit code is 0, or the id of the first check that failed.
test: $(SCROLL_TEST_BIN)
	@$(SIM65) $(SCROLL_TEST_BIN); \
	code=$$?; \
	if [ $$code -eq 0 ]; then \
		echo "scroll_rgn: all checks passed"; \
	else \
		echo "scroll_rgn: FAILED at check $$code (see $(SCROLL_TEST_SRC))"; \
		exit 1; \
	fi

$(SCROLL_TEST_BIN): $(SCROLL_TEST_SRC) scroll_rgn.inc
	@mkdir -p $(BUILD_DIR)
	$(CL65) -t sim6502 --asm-include-dir . -o $@ $(SCROLL_TEST_SRC)

vbxe-lib: $(VBXE_LIB)

$(VBXE_LIB_OBJ): $(VBXE_LIB_SRC) $(CA65_DEPS)
	$(CA65) $(VBXE_LIB_SRC) -o $(VBXE_LIB_OBJ)

$(VBXE_LIB): $(VBXE_LIB_OBJ)
	$(AR65) a $@ $<

ca65: $(CA65_XEX)

$(CA65_OBJ): $(CA65_SRC) $(CA65_MAIN_DEPS)
	$(CA65) $(CA65_SRC) -o $(CA65_OBJ)

$(CA65_XEX): $(CA65_OBJ) $(VBXE_LIB)
	$(LD65) -C $(CA65_CFG) -S $(START_ADDR) -D start=$(START_ADDR) --mapfile $(PROJ_NAME)_ca65.map $(CA65_OBJ) $(VBXE_LIB) -o $(CA65_XEX)

ca65-disk: $(CA65_ATR)

$(CA65_ATR): $(CA65_XEX)
	cp $(CA65_XEX) $(DISK_DIR)/$(PROJ_NAME).AR1
	dir2atr -b MyDos4534 720 $(CA65_ATR) $(DISK_DIR)/

disk: ca65-disk mads-disk

mads: $(MADS_XEX)

$(MADS_XEX): $(MADS_SRC) $(MADS_DEPS)
	$(MADS) $(MADS_SRC) -o:$(MADS_XEX)

mads-disk: $(MADS_ATR)

$(MADS_ATR): $(MADS_XEX)
	cp $(MADS_XEX) $(DISK_DIR)/$(PROJ_NAME).AR1
	dir2atr -b MyDos4534 720 $(MADS_ATR) $(DISK_DIR)/

clean:
	rm -f $(MADS_XEX) $(MADS_ATR) $(CA65_OBJ) $(CA65_XEX) $(CA65_ATR) $(VBXE_LIB_OBJ) $(VBXE_LIB)
	rm -rf $(BUILD_DIR)
