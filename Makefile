APP := KeyboardLock.app
INSTALL_DIR := /Applications

.PHONY: build install run uninstall reset-permission clean

build:
	./build.sh

install: build
	-pkill -x KeyboardLock
	rm -rf "$(INSTALL_DIR)/$(APP)"
	ditto "$(APP)" "$(INSTALL_DIR)/$(APP)"
	@echo "Installed to $(INSTALL_DIR)/$(APP)"

run:
	open -a "$(INSTALL_DIR)/$(APP)"

uninstall:
	-pkill -x KeyboardLock
	rm -rf "$(INSTALL_DIR)/$(APP)"
	-tccutil reset Accessibility local.keyboardlock

reset-permission:
	tccutil reset Accessibility local.keyboardlock

clean:
	rm -rf build "$(APP)"
