XSLTPROC:=/usr/bin/xsltproc
XSLPREFIX:=http://docbook.sourceforge.net/release/xsl-ns/current

manpages:=genkernel.8

%: %.xml
	$(XSLTPROC) -o $@ -nonet $(XSLPREFIX)/manpages/docbook.xsl $<

.PHONY: clean

all: $(manpages)

clean:
	-$(RM) $(manpages)
