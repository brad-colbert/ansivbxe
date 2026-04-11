ASM       = mads
PROJ_NAME = ANSIVBXE
SRC       = $(PROJ_NAME).asm
XEX       = $(PROJ_NAME).XEX
ATR       = $(PROJ_NAME).ATR
DISK_DIR  = disk
DEPS      = atarios.equ atarihardware.equ VBXE.equ

.PHONY: all disk clean

all: $(XEX)

$(XEX): $(SRC) $(DEPS)
	$(ASM) $(SRC) -o:$(XEX)

disk: $(ATR)

$(ATR): $(XEX)
	cp $(XEX) $(DISK_DIR)/$(PROJ_NAME).AR1
	dir2atr -b MyDos4534 720 $(ATR) $(DISK_DIR)/

clean:
	rm -f $(XEX) $(ATR)
