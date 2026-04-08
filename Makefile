ASM      = mads
SRC      = ANSIVBXE.asm
XEX      = ANSIVBXE.XEX
ATR      = ANSIVBXE.ATR
DISK_DIR = disk
DEPS     = atarios.equ atarihardware.equ VBXE.equ

.PHONY: all disk clean

all: $(XEX)

$(XEX): $(SRC) $(DEPS)
	$(ASM) $(SRC) -o:$(XEX)

disk: $(ATR)

$(ATR): $(XEX)
	cp $(XEX) $(DISK_DIR)/$(XEX)
	dir2atr -b Dos25 720 $(ATR) $(DISK_DIR)/

clean:
	rm -f $(XEX) $(ATR)
