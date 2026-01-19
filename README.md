# CV system (with automatic citations from PMDIs)

Write `PMID:########` in Markdown. The build fetches PubMed metadata and expands each PMID to a fully formatted reference line via a Pandoc Lua filter.

## Install

- pandoc
- TeX (MacTeX/TeX Live) for PDF output
- python3 + requests: `python3 -m pip install requests`

Recommended env vars:
- `export NCBI_EMAIL="you@institution.edu"`
- Optional: `export NCBI_API_KEY="..."`

## Build

- `make pdf`  -> build/cv.pdf
- `make html` -> build/cv.html
- `make docx` -> build/cv.docx

## Authoring

In cv.md, include references as:
- `PMID:40424645`

Control formatting via Makefile metadata:
- `-M pmid_style=cv` or `short`
- `-M pmid_authors=6`
