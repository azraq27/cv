# Makefile - PMID-only CV build
#
# Requirements:
# - pandoc
# - xelatex (TeX Live / MacTeX)
# - python3 + requests (pip install requests)
#
# Optional (recommended):
# - export NCBI_EMAIL="you@domain.edu"
# - export NCBI_API_KEY="..."

MD=cv.md
TEMPLATE=template.tex
FILTER=filters/pmid_citations.lua
PUBDB=.cache/pubmed.json
OUTDIR=build

PANDOC=pandoc
PDFENGINE=xelatex

.PHONY: pdf html docx clean references

references: $(PUBDB)

$(PUBDB): $(MD) scripts/pmid_fetch.py
	python3 scripts/pmid_fetch.py --md $(MD) --out $(PUBDB)

pdf: references
	mkdir -p $(OUTDIR)
	$(PANDOC) $(MD) \
	  --template=$(TEMPLATE) \
	  --lua-filter=$(FILTER) \
	  -M pmid_db=$(PUBDB) \
	  -M pmid_style=cv \
	  -M pmid_authors=6 \
	  --pdf-engine=$(PDFENGINE) \
	  -o $(OUTDIR)/cv.pdf

html: references
	mkdir -p $(OUTDIR)
	$(PANDOC) $(MD) \
	  --lua-filter=$(FILTER) \
	  -M pmid_db=$(PUBDB) \
	  -M pmid_style=cv \
	  -M pmid_authors=6 \
	  -o $(OUTDIR)/cv.html

docx: references
	mkdir -p $(OUTDIR)
	$(PANDOC) $(MD) \
	  --lua-filter=$(FILTER) \
	  -M pmid_db=$(PUBDB) \
	  -M pmid_style=cv \
	  -M pmid_authors=6 \
	  -o $(OUTDIR)/cv.docx

clean:
	rm -rf $(OUTDIR)
