SBCL   ?= sbcl
PREFIX ?= $(HOME)/.local

SOURCES := <% @var application-name %>.asd build.lisp $(shell find src -name '*.lisp')

<% @var application-name %>: $(SOURCES)
	vend get
	$(SBCL) --non-interactive \
	        --load build.lisp

install: <% @var application-name %>
	install -d $(PREFIX)/bin
	install -m 755 <% @var application-name %> $(PREFIX)/bin/<% @var application-name %>

uninstall:
	rm -f $(PREFIX)/bin/<% @var application-name %>

clean:
	rm -f <% @var application-name %>

.PHONY: install uninstall clean
