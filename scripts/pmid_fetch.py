#!/usr/bin/env python3
"""
pmid_fetch.py
Fetch PubMed metadata for PMIDs (from a markdown file, a pmids.txt file, or CLI args)
and write a local JSON database used by the Pandoc Lua filter.

This is a PMID-only workflow: you write `PMID:########` in Markdown and the build expands
it to a formatted reference line.

Inputs (choose any):
- --md cv.md               (extracts PMIDs from lines containing 'PMID:')
- --pmids-file pmids.txt   (one PMID per line)
- positional args          (PMIDs)
Output:
- --out .cache/pubmed.json

NCBI guidance:
- Provide --email (or env NCBI_EMAIL). Optional --api-key (env NCBI_API_KEY).

Usage:
  python3 scripts/pmid_fetch.py --md cv.md --out .cache/pubmed.json
  python3 scripts/pmid_fetch.py --pmids-file pmids.txt -o .cache/pubmed.json
  python3 scripts/pmid_fetch.py 31314747 40424645 -o .cache/pubmed.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Sequence

from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
PMID_RE = re.compile(r"\bPMID\s*:\s*(\d+)\b", re.IGNORECASE)
DIGITS_RE = re.compile(r"^\d+$")

def extract_pmids_from_md(md_path: Path) -> List[str]:
    txt = md_path.read_text(encoding="utf-8")
    return list(dict.fromkeys(PMID_RE.findall(txt)))  # preserve order, unique

def load_pmids_file(path: Path) -> List[str]:
    pmids: List[str] = []
    for ln in path.read_text(encoding="utf-8").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        if ln.lower().startswith("pmid"):
            m = PMID_RE.search(ln)
            if m:
                pmids.append(m.group(1))
        elif DIGITS_RE.match(ln):
            pmids.append(ln)
    return list(dict.fromkeys(pmids))

def chunk(seq: Sequence[str], n: int) -> List[List[str]]:
    return [list(seq[i:i+n]) for i in range(0, len(seq), n)]

def fetch_esummary(pmids: Sequence[str], email: str | None, api_key: str | None,
                   timeout_s: int = 30, delay_s: float = 0.34) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for group in chunk(list(pmids), 200):
        params = {"db": "pubmed", "id": ",".join(group), "retmode": "json"}
        if email:
            params["email"] = email
        if api_key:
            params["api_key"] = api_key
        qs = urlencode(params)
        req = Request(
            f"{EUTILS}/esummary.fcgi?{qs}",
            headers={"User-Agent": "pmid_fetch/1.0 (+https://www.ncbi.nlm.nih.gov/)"},
        )
        try:
            with urlopen(req, timeout=timeout_s) as resp:
                if resp.status != 200:
                    raise RuntimeError(f"HTTP {resp.status} from NCBI: {req.full_url}")
                j = json.loads(resp.read().decode("utf-8"))
        except (HTTPError, URLError) as exc:
            raise RuntimeError(f"Failed to fetch PubMed data: {exc}") from exc
        result = j.get("result", {})
        for uid in result.get("uids", []):
            out[str(uid)] = result.get(str(uid), {})
        time.sleep(delay_s)
    return out

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pmids", nargs="*", help="PMIDs")
    ap.add_argument("--md", help="Markdown file to scan for 'PMID:####'")
    ap.add_argument("--pmids-file", help="pmids.txt file (one PMID per line)")
    ap.add_argument("-o", "--out", default=".cache/pubmed.json", help="Output JSON database")
    ap.add_argument("--merge", action="store_true", help="Merge with existing out file (default true if file exists)")
    ap.add_argument("--email", default=os.getenv("NCBI_EMAIL"), help="Email for NCBI (recommended)")
    ap.add_argument("--api-key", default=os.getenv("NCBI_API_KEY"), help="NCBI API key (optional)")
    args = ap.parse_args()

    pmids: List[str] = []
    if args.md:
        pmids += extract_pmids_from_md(Path(args.md))
    if args.pmids_file:
        pmids += load_pmids_file(Path(args.pmids_file))
    pmids += [p.strip() for p in args.pmids if p.strip()]

    pmids = [p for p in pmids if DIGITS_RE.match(p)]
    pmids = list(dict.fromkeys(pmids))

    if not pmids:
        print("No PMIDs found.", file=sys.stderr)
        return 2

    out_path = Path(args.out)
    existing: Dict[str, Any] = {}
    do_merge = args.merge or out_path.exists()
    if do_merge and out_path.exists():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
        except Exception:
            existing = {}

    missing = [p for p in pmids if p not in existing]
    if missing:
        fetched = fetch_esummary(missing, email=args.email, api_key=args.api_key)
        existing.update(fetched)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(existing, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Wrote {out_path} ({len(existing)} records; {len(missing)} fetched).")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
