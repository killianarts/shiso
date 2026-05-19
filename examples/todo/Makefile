SBCL   ?= sbcl
PREFIX ?= $(HOME)/.local

SOURCES := todo.asd build.lisp $(shell find src -name '*.lisp')

todo: $(SOURCES)
	vend get
	$(SBCL) --non-interactive \
	        --load build.lisp \
	        --eval '(asdf:make :todo)'

install: todo
	install -d $(PREFIX)/bin
	install -m 755 todo $(PREFIX)/bin/todo

uninstall:
	rm -f $(PREFIX)/bin/todo

clean:
	rm -f todo

.PHONY: install uninstall clean
