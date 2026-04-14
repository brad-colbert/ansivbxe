MADS      ?= mads
CA65      ?= ca65
LD65      ?= ld65

PROJ_NAME   = ANSIVBXE
DISK_DIR    = disk

MADS_SRC    = $(PROJ_NAME).asm
MADS_DEPS   = atarios.equ atarihardware.equ VBXE.equ
MADS_XEX    = $(PROJ_NAME).XEX
MADS_ATR    = $(PROJ_NAME).ATR

CA65_SRC    = $(PROJ_NAME)_ca65.asm
CA65_DEPS   = atarios_ca65.inc atarihardware_ca65.inc VBXE_ca65.inc
CA65_OBJ    = $(PROJ_NAME)_ca65.o
CA65_XEX    = $(PROJ_NAME)_ca65.XEX
CA65_ATR    = $(PROJ_NAME)_ca65.ATR
CA65_CFG    ?= /usr/local/share/cc65/cfg/atari-asm-xex.cfg
START_ADDR  ?= 0x2800

.PHONY: all disk ca65 ca65-disk mads mads-disk clean

all: mads ca65

ca65: $(CA65_XEX)

$(CA65_OBJ): $(CA65_SRC) $(CA65_DEPS)
	$(CA65) $(CA65_SRC) -o $(CA65_OBJ)

$(CA65_XEX): $(CA65_OBJ)
	$(LD65) -C $(CA65_CFG) -S $(START_ADDR) -D start=$(START_ADDR) $(CA65_OBJ) -o $(CA65_XEX)

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
	rm -f $(MADS_XEX) $(MADS_ATR) $(CA65_OBJ) $(CA65_XEX) $(CA65_ATR)
