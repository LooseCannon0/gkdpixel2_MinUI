ifeq (,$(CROSS_COMPILE))
$(error missing CROSS_COMPILE for this toolchain)
endif
ifeq (,$(PREFIX))
$(error missing PREFIX for this toolchain)
endif

TARGET=msettings

.PHONY: build
.PHONY: clean

CC = $(CROSS_COMPILE)gcc

# warning-clean at -O2 with _FORTIFY_SOURCE (Ubuntu's gcc enables it whenever
# optimizing), so -Werror is safe here
CFLAGS = -O2 -Wall -Werror -fpic
LDFLAGS = -ldl -lrt -s

build:
	$(CC) -c $(CFLAGS) "$(TARGET).c"
	$(CC) -shared -o "lib$(TARGET).so" "$(TARGET).o" $(LDFLAGS)
	cp "$(TARGET).h" "$(PREFIX)/include"
	cp "lib$(TARGET).so" "$(PREFIX)/lib"
clean:
	rm -f *.o
	rm -f "lib$(TARGET).so"
	rm -f $(PREFIX)/include/$(TARGET).h
	rm -f $(PREFIX)/lib/lib$(TARGET).so
