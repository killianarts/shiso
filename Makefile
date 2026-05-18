LISP     ?= sbcl
PREFIX   ?= $(HOME)/.local
ASDF_DIR ?= $(HOME)/common-lisp

SOURCES := shiso.asd build.lisp $(shell find src -name '*.lisp')

shiso: $(SOURCES)
	vend get
	$(LISP) --load build.lisp

install: shiso
	install -d $(PREFIX)/bin
	install -m 755 shiso $(PREFIX)/bin/shiso
	rm -rf $(ASDF_DIR)/shiso
	install -d $(ASDF_DIR)
	cp -R $(CURDIR) $(ASDF_DIR)/shiso

uninstall:
	rm -f $(PREFIX)/bin/shiso
	rm -rf $(ASDF_DIR)/shiso

test:
	$(LISP) --load test.lisp

clean:
	rm -f shiso

distclean: clean
	rm -rf vendored

.PHONY: install uninstall test clean distclean
