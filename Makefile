PACKAGE_VERSION = `/bin/fgrep GK_V= genkernel | sed "s/.*GK_V='\([^']\+\)'/\1/"`
distdir = genkernel-$(PACKAGE_VERSION)

XSLTPROC:=/usr/bin/xsltproc
XSLPREFIX:=http://docbook.sourceforge.net/release/xsl-ns/current

manpages:=genkernel.8

%: %.xml
	$(XSLTPROC) -o $@ -nonet $(XSLPREFIX)/manpages/docbook.xsl $<

all: $(manpages)

clean:
	-$(RM) $(manpages)

check-git-repository:
	git diff --quiet || { echo 'STOP, you have uncommitted changes in the working directory' ; false ; }
	git diff --cached --quiet || { echo 'STOP, you have uncommitted changes in the index' ; false ; }

dist: check-git-repository genkernel.8
	rm -Rf "$(distdir)" "$(distdir)".tar "$(distdir)".tar.bz2
	mkdir "$(distdir)"
	git ls-files -z | xargs -0 cp --no-dereference --parents --target-directory="$(distdir)" \
		$(EXTRA_DIST)
	tar cf "$(distdir)".tar "$(distdir)"
	bzip2 -9v "$(distdir)".tar
	rm -Rf "$(distdir)"

.PHONY: clean check-git-repository dist
