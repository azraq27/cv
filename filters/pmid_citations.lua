-- pmid_citations.lua
-- Pandoc Lua filter: replace `PMID:####` with a formatted reference string using a local JSON db.
--
-- Build flow:
--   1) python3 scripts/pmid_fetch.py --md cv.md --out .cache/pubmed.json
--   2) pandoc cv.md --lua-filter=filters/pmid_citations.lua -M pmid_db=.cache/pubmed.json ...

local json = require('pandoc.json')

local db = nil
local db_loaded_path = nil
local cfg = { style = "cv", max_authors = 6 }

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

local function format_authors(authors, maxn)
  if not authors or #authors == 0 then return "" end
  maxn = maxn or 6
  local use_etal = (#authors > maxn)
  local n = math.min(#authors, maxn)
  local out = {}
  for i=1,n do table.insert(out, authors[i]) end
  local s = table.concat(out, ", ")
  if use_etal then s = s .. ", et al." end
  return s
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

local function format_reference(raw, pmid, style, max_authors)
  local authors = {}
  if raw.authors then
    for _, a in ipairs(raw.authors) do
      if a.name then table.insert(authors, a.name) end
    end
  end

  local a_str = format_authors(authors, max_authors)
  local title = clean_title(raw.title or "")
  local journal = raw.source or raw.fulljournalname or ""
  local year = first_year(raw.pubdate or "")
  local volume = raw.volume or ""
  local issue = raw.issue or ""
  local pages = raw.pages or ""
  local doi = extract_doi(raw.articleids)

  if style == "short" then
    local parts = {}
    if a_str ~= "" then table.insert(parts, a_str) end
    if journal ~= "" then table.insert(parts, journal) end
    if year ~= "" then table.insert(parts, year) end
    table.insert(parts, "PMID:" .. pmid)
    return table.concat(parts, ". ") .. "."
  end

  local out = {}
  if a_str ~= "" then
    table.insert(out, a_str .. " (" .. year .. ") " .. title .. ".")
  else
    table.insert(out, "(" .. year .. ") " .. title .. ".")
  end

  local vinfo = ""
  if volume ~= "" then vinfo = volume end
  if issue ~= "" then vinfo = vinfo .. "(" .. issue .. ")" end
  if pages ~= "" then
    if vinfo ~= "" then vinfo = vinfo .. ":" .. pages else vinfo = pages end
  end

  if journal ~= "" and vinfo ~= "" then
    table.insert(out, journal .. "; " .. vinfo .. ".")
  elseif journal ~= "" then
    table.insert(out, journal .. ".")
  elseif vinfo ~= "" then
    table.insert(out, vinfo .. ".")
  end

  if doi and doi ~= "" then
    table.insert(out, "DOI:" .. doi .. ".")
  end

  table.insert(out, "PMID:" .. pmid .. ".")

  return table.concat(out, " ")
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

  return pandoc.Str(format_reference(raw, pmid, style, max_authors))
end
