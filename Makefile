# Makefile for Pandoc.

#-------------------------------------------------------------------------------
# Cabal constants
#-------------------------------------------------------------------------------
CABAL       := $(wildcard *.cabal)
NAME        := $(shell sed -ne 's/^[Nn]ame:[[:space:]]*//p' $(CABAL))
THIS        := $(shell echo $(NAME) | tr A-Z a-z)
VERSION     := $(shell sed -ne 's/^[Vv]ersion:[[:space:]]*//p' $(CABAL))
EXECUTABLES := $(shell sed -ne 's/^[Ee]xecutable:[[:space:]]*//p' $(CABAL))

#-------------------------------------------------------------------------------
# Variables to setup through environment
#-------------------------------------------------------------------------------
PREFIX      ?= /usr/local
DESTDIR     ?=

#-------------------------------------------------------------------------------
# Constant names and commands in source tree
#-------------------------------------------------------------------------------
SRCDIR      := src
MANDIR      := man
BUILDDIR    := dist
BUILDCONF   := .setup-config
BUILDCMD    := runhaskell Setup.hs

#-------------------------------------------------------------------------------
# Installation paths
#-------------------------------------------------------------------------------
BINPATH     := $(DESTDIR)$(PREFIX)/bin
DATAPATH    := $(DESTDIR)$(PREFIX)/share
DOCPATH     := $(DATAPATH)/doc/$(THIS)
LIBDOCPATH  := $(DATAPATH)/doc/$(THIS)-doc
MANPATH     := $(DATAPATH)/man
PKGPATH     := $(DATAPATH)/$(THIS)

#-------------------------------------------------------------------------------
# Generic Makefile variables
#-------------------------------------------------------------------------------
INSTALL         := install -c
INSTALL_PROGRAM := $(INSTALL) -m 755 
INSTALL_DATA    := $(INSTALL) -m 644

#-------------------------------------------------------------------------------
# Recipes
#-------------------------------------------------------------------------------

.PHONY: all
all: build

.PHONY: templates
templates: $(SRCDIR)/templates
$(SRCDIR)/templates:
	$(MAKE) -C $(SRCDIR)/templates

.PHONY: prep
prep: 
	# Darcs cannot preserve file permissions.
	-for p in configure debian/rules; do chmod +x $$p; done

.PHONY: configure
cleanup_files+=$(BUILDDIR) $(BUILDCONF) $(CABAL:%.cabal=%).buildinfo
configure: $(BUILDCONF)
$(BUILDCONF): prep
	$(BUILDCMD) configure --prefix=$(PREFIX)

.PHONY: build
build: templates configure
	$(BUILDCMD) build

.PHONY: build-lib-doc
build-lib-doc: html
cleanup_files+=html
html: $(BUILDCONF)
	$(BUILDCMD) haddock && mv $(BUILDDIR)/doc/html .

cleanup_files+=$(EXECUTABLES)
$(EXECUTABLES): build
	# Ugly kludge to seperate program and library installations.
	# Leave the library installation to Cabal ('install-lib' target).
	find $(BUILDDIR) -type f -name "$(EXECUTABLES)" -perm +a=x -exec mv {} . \;


# XXX: Note that we don't handle PREFIX correctly at the install-* stages,
# i.e. any PREFIX given at the configuration time is lost, unless it is
# also supplied (via environment) at these stages.
.PHONY: install-exec uninstall-exec
bin_all:=$(EXECUTABLES) html2markdown markdown2latex latex2markdown markdown2pdf
install-exec: $(bin_all)
	$(INSTALL) -d $(BINPATH); \
	for p in $(bin_all); do $(INSTALL_PROGRAM) $$p $(BINPATH)/; done
uninstall-exec:
	-for p in $(bin_all); do rm -f $(BINPATH)/$$p; done

.PHONY: install-doc uninstall-doc
doc_all:=README.html README BUGS TODO
cleanup_files+=README.html
install-doc: $(doc_all)
	$(INSTALL) -d $(DOCPATH) && $(INSTALL_DATA) $(doc_all) $(DOCPATH)/; \
	$(INSTALL) -d $(MANPATH) && cp -a $(MANDIR)/* $(MANPATH)/
uninstall-doc:
	-for d in $(doc_all); do rm -f $(DOCPATH)/$$d; done
	-cd $(MANDIR) && find . -type f -exec rm -f "$(MANPATH)/{}" \;

# Handle program installation manually (due to the deficiencies in Cabal).
.PHONY: install uninstall
install: install-exec install-doc
# FIXME: incomplete support for uninstallation.
uninstall: uninstall-exec uninstall-doc

.PHONY: install-lib install-lib-doc
install-lib:
	@$(BUILDCMD) install || true # required since we move executable
install-lib-doc: build-lib-doc
	$(INSTALL) -d $(LIBDOCPATH) && cp -a html $(LIBDOCPATH)/

.PHONY: test test-markdown
test: $(EXECUTABLES)
	@cd tests && perl runtests.pl -s $(PWD)/$(THIS)
test-markdown: $(EXECUTABLES)
	@cd tests/MarkdownTest_1.0.3 && perl MarkdownTest.pl -s $(PWD)/$(THIS) -tidy
%.html: %
	./$(THIS) -s $^ >$@ || rm -f $@

# Stolen and slightly improved from a GPLed Makefile.  Credits to John Meacham.
src_all:=$(shell find $(SRCDIR) -type f -name '*hs' | egrep -v '^\./(_darcs|lib|test)/')
cleanup_files+=$(patsubst %,$(SRCDIR)/%,tags tags.sorted)
tags: $(src_all)
	cd $(SRCDIR) && hasktags -c $(src_all:$(SRCDIR)/%=%); \
	LC_ALL=C sort tags >tags.sorted; mv tags.sorted tags

deb: debian prep
	if [ -x /usr/bin/debuild ]; then \
		debuild -i_darcs -I_darcs -uc -us; \
	else \
		echo "*** Please install devscripts package. ***"; \
		dpkg-buildpackage -i_darcs -I_darcs -uc -us; \
	fi

.PHONY: distclean clean
distclean: clean prep
	if [ -d debian ]; then fakeroot debian/rules clean; fi
clean:
	-if [ -f $(BUILDCONF) ]; then $(BUILDCMD) clean; fi
	-rm -rf $(cleanup_files)

