SBCL   ?= sbcl
PREFIX ?= $(HOME)/.local

SOURCES := mysite.asd build.lisp $(shell find src -name '*.lisp')

mysite: $(SOURCES)
	vend get
	$(SBCL) --non-interactive \
	        --load build.lisp \
	        --eval '(asdf:make :mysite)'

install: mysite
	install -d $(PREFIX)/bin
	install -m 755 mysite $(PREFIX)/bin/mysite

uninstall:
	rm -f $(PREFIX)/bin/mysite

clean:
	rm -f mysite

.PHONY: install uninstall clean
