-- pmid_citations.lua
-- Replace PMID tokens with formatted citations.
-- For LaTeX output, emit \cvpub{...} entries to produce true hanging-indent bibliography list.

local json = require('pandoc.json')

local db = nil
local db_loaded_path = nil
local cfg = {
  style = "cv",
  max_authors = 6,
  -- Name to bold: default matches your CV.
  bold_family = "Gross",
  bold_initials = "WL",
}

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function load_db(path)
  local txt = read_file(path)
  if not txt then
    io.stderr:write("[pmid_citations] Could not read PubMed db at: " .. path .. "\n")
    return {}
  end
  local ok, parsed = pcall(json.decode, txt)
  if not ok then
    io.stderr:write("[pmid_citations] Failed to parse JSON db: " .. path .. "\n")
    return {}
  end
  return parsed
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_year(pubdate)
  if not pubdate or pubdate == "" then return "" end
  local y = pubdate:match("^(%d%d%d%d)")
  return y or ""
end

local function extract_doi(articleids)
  if not articleids then return nil end
  for _, a in ipairs(articleids) do
    if a.idtype == "doi" and a.value and a.value ~= "" then
      return a.value
    end
  end
  return nil
end

local function clean_title(title)
  if not title then return "" end
  title = trim(title):gsub("%s+", " ")
  title = title:gsub("%.$", "")
  return title
end

local function lookup_pmid(db_tbl, pmid)
  if not db_tbl then return nil end
  if db_tbl[pmid] then return db_tbl[pmid] end
  local as_num = tonumber(pmid)
  if as_num and db_tbl[as_num] then return db_tbl[as_num] end
  if db_tbl[tostring(pmid)] then return db_tbl[tostring(pmid)] end
  return nil
end

local function count_records(db_tbl)
  if not db_tbl then return 0 end
  local n = 0
  for _ in pairs(db_tbl) do n = n + 1 end
  return n
end

local function meta_lookup(meta_tbl, key)
  if not meta_tbl then return nil end
  local ok, val = pcall(function() return meta_tbl[key] end)
  if not ok then return nil end
  return val
end

local function ensure_db(meta)
  if db_loaded_path then return end
  local meta_tbl = meta or {}
  local db_path = ".cache/pubmed.json"
  local from_meta = meta_lookup(meta_tbl, "pmid_db")
  if from_meta then db_path = tostring(from_meta) end
  db = load_db(db_path)
  db_loaded_path = db_path
  io.stderr:write(string.format("[pmid_citations] Loaded %d records from %s\n", count_records(db), db_path))
  io.stderr:flush()
end

-- Helpers to create inlines
local function S(t) return pandoc.Str(t) end
local function SP(t) return pandoc.Space() end
local function R(tex) return pandoc.RawInline("latex", tex) end

-- Detect and bold "Gross WL" author tokens as PubMed typically provides: "Gross WL"
-- Also catch "Gross, WL" (rare) and "Gross W L".
local function is_target_author(author_str)
  if not author_str or author_str == "" then return false end
  local s = author_str

  -- Normalize: remove periods, collapse spaces, remove commas
  s = s:gsub("%.", "")
  s = s:gsub(",", "")
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

  -- Expect forms like "Gross WL" or "Gross W L"
  if not s:match("^" .. cfg.bold_family .. "%s") then return false end

  -- initials part after family
  local initials = s:gsub("^" .. cfg.bold_family .. "%s+", "")
  initials = initials:gsub("%s+", "")

  return (initials == cfg.bold_initials)
end

local function author_inline(author_str)
  if is_target_author(author_str) then
    if FORMAT and FORMAT:match("latex") then
      return { R("\\textbf{"), S(author_str), R("}") }
    else
      return { pandoc.Strong({ S(author_str) }) }
    end
  else
    return { S(author_str) }
  end
end

local function join_authors(authors, maxn)
  local inlines = {}
  if not authors or #authors == 0 then return inlines end

  maxn = maxn or 6
  local use_etal = (#authors > maxn)
  local n = math.min(#authors, maxn)

  for i=1,n do
    local a = authors[i]
    local name = a
    -- author entries come from PubMed as "Last FM" in esummary
    for _, x in ipairs(author_inline(name)) do table.insert(inlines, x) end
    if i < n then
      table.insert(inlines, S(","))
      table.insert(inlines, SP())
    end
  end

  if use_etal then
    table.insert(inlines, S(","))
    table.insert(inlines, SP())
    table.insert(inlines, S("et"))
    table.insert(inlines, SP())
    table.insert(inlines, S("al."))
  end

  return inlines
end

-- Insert LaTeX allowbreak points after DOI punctuation, but ONLY as raw LaTeX inlines
local function doi_inlines(doi)
  local inlines = {}
  for c in doi:gmatch(".") do
    table.insert(inlines, S(c))
    if FORMAT and FORMAT:match("latex") then
      if c == "/" or c == "." or c == "-" or c == "_" then
        -- Terminate the control sequence so following letters don't attach.
        table.insert(inlines, R("\\allowbreak{}"))
      end
    end
  end
  return inlines
end

local function format_reference_inlines(raw, pmid, style, max_authors)
  local authors = {}
  if raw.authors then
    for _, a in ipairs(raw.authors) do
      if a.name then table.insert(authors, a.name) end
    end
  end

  local title = clean_title(raw.title or "")
  local journal = raw.source or raw.fulljournalname or ""
  local year = first_year(raw.pubdate or "")
  local volume = raw.volume or ""
  local issue = raw.issue or ""
  local pages = raw.pages or ""
  local doi = extract_doi(raw.articleids)

  local out = {}

  -- Authors.
  local a_in = join_authors(authors, max_authors)
  for _, x in ipairs(a_in) do table.insert(out, x) end
  if #a_in > 0 then
    table.insert(out, S("."))
    table.insert(out, SP())
  end

  -- Year and title.
  if year ~= "" then
    table.insert(out, S("(" .. year .. ")"))
    table.insert(out, SP())
  end
  if title ~= "" then
    table.insert(out, S(title .. "."))
    table.insert(out, SP())
  end

  -- Journal; vol(issue):pages.
  local vinfo = ""
  if volume ~= "" then vinfo = volume end
  if issue ~= "" then vinfo = vinfo .. "(" .. issue .. ")" end
  if pages ~= "" then
    if vinfo ~= "" then vinfo = vinfo .. ":" .. pages else vinfo = pages end
  end

  if journal ~= "" then
    if vinfo ~= "" then
      table.insert(out, S(journal .. "; " .. vinfo .. "."))
    else
      table.insert(out, S(journal .. "."))
    end
    table.insert(out, SP())
  elseif vinfo ~= "" then
    table.insert(out, S(vinfo .. "."))
    table.insert(out, SP())
  end

  -- DOI (lowercase label as in your examples)
  if doi and doi ~= "" then
    table.insert(out, S("doi:"))
    for _, x in ipairs(doi_inlines(doi)) do table.insert(out, x) end
    table.insert(out, S("."))
    table.insert(out, SP())
  end

  -- PMID always at end
  table.insert(out, S("PMID:" .. pmid .. "."))

  return out
end

function Meta(meta)
  ensure_db(meta)

  local style_from_meta = meta_lookup(meta, "pmid_style")
  if style_from_meta then cfg.style = tostring(style_from_meta) end

  local authors_from_meta = meta_lookup(meta, "pmid_authors")
  if authors_from_meta then
    local n = tonumber(tostring(authors_from_meta))
    if n then cfg.max_authors = n end
  end

  -- Optional: allow override in YAML meta if desired
  local bold_family = meta_lookup(meta, "pmid_bold_family")
  local bold_initials = meta_lookup(meta, "pmid_bold_initials")
  if bold_family then cfg.bold_family = tostring(bold_family) end
  if bold_initials then cfg.bold_initials = tostring(bold_initials) end

  return meta
end

function Str(el)
  if not el.text then return nil end
  if not el.text:match("[Pp][Mm][Ii][Dd]%s*:") then return nil end

  local pmid = el.text:match("[Pp][Mm][Ii][Dd]%s*:%s*(%d+)")
  if not pmid then return nil end

  ensure_db()
  local raw = lookup_pmid(db, pmid)
  if not raw then
    io.stderr:write("[pmid_citations] Missing PMID in db: " .. pmid .. " (run scripts/pmid_fetch.py)\n")
    return nil
  end

  local style = cfg.style or "cv"
  local max_authors = cfg.max_authors or 6

  local inlines = format_reference_inlines(raw, pmid, style, max_authors)

  -- For LaTeX output: wrap each citation as \cvpub{...}
  if FORMAT and FORMAT:match("latex") then
    -- Emit: \cvpub{<inlines>}
    -- Using RawInline for the wrapper braces so LaTeX sees the macro and arguments.
    local wrapped = {}
    table.insert(wrapped, R("\\cvpub{"))
    for _, x in ipairs(inlines) do table.insert(wrapped, x) end
    table.insert(wrapped, R("}"))
    return pandoc.Span(wrapped)
  end

  -- Other formats: just return the citation inlines
  return pandoc.Span(inlines)
end
