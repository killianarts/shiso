SBCL   ?= sbcl
PREFIX ?= $(HOME)/.local

SOURCES := <% @var name %>.asd build.lisp $(shell find src -name '*.lisp')

<% @var name %>: $(SOURCES)
	vend get
	$(SBCL) --non-interactive \
	        --load build.lisp \
	        --eval '(asdf:make :<% @var name %>)'

install: <% @var name %>
	install -d $(PREFIX)/bin
	install -m 755 <% @var name %> $(PREFIX)/bin/<% @var name %>

uninstall:
	rm -f $(PREFIX)/bin/<% @var name %>

clean:
	rm -f <% @var name %>

.PHONY: install uninstall clean
