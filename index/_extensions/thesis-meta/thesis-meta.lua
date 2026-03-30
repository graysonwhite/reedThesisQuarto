-- Lua filter to inject thesis metadata and front matter for Reed College thesis
-- This filter:
-- 1. Sets LaTeX metadata commands (title, author, date, institution, etc.) via header-includes
-- 2. Inserts front matter content directly into the document
-- 3. Supports short List of Figures/Tables entries via metadata lookup tables
--
-- SHORT CAPTIONS
-- Quarto does not pass chunk options (like #| fig-scap:) through to the Pandoc
-- Figure element's attributes, so chunk-level options cannot be used for this.
-- Instead, define short captions in _quarto.yml using these top-level keys:
--
--   fig-scaps:
--     fig-my-label: "Short text for List of Figures"
--     fig-another:  "Another short text"
--   tbl-scaps:
--     tbl-my-table: "Short text for List of Tables"
--
-- For Markdown images (not code chunks) you can also use an inline attribute:
--   ![Full caption](image.png){fig-scap="Short text"}

-- Helper function to get string value from metadata
local function get_string(meta, field)
  if meta[field] then
    if type(meta[field]) == "table" then
      return pandoc.utils.stringify(meta[field])
    else
      return tostring(meta[field])
    end
  end
  return nil
end

-- Helper function to get boolean value from metadata
local function get_bool(meta, field)
  if meta[field] then
    if type(meta[field]) == "boolean" then
      return meta[field]
    elseif type(meta[field]) == "table" then
      local val = pandoc.utils.stringify(meta[field])
      return val == "true" or val == "yes"
    else
      local val = tostring(meta[field])
      return val == "true" or val == "yes"
    end
  end
  return false
end

-- Lookup tables populated from fig-scaps / tbl-scaps metadata
local fig_scaps = {}
local tbl_scaps = {}

-- Store metadata globally for use in Pandoc filter
local stored_meta = nil

function Meta(meta)
  -- Only process for LaTeX/PDF output
  if not quarto.doc.is_format("pdf") then
    return meta
  end

  stored_meta = meta

  -- Build short-caption lookup tables from metadata
  if meta["fig-scaps"] then
    for id, val in pairs(meta["fig-scaps"]) do
      fig_scaps[id] = pandoc.utils.stringify(val)
    end
  end
  if meta["tbl-scaps"] then
    for id, val in pairs(meta["tbl-scaps"]) do
      tbl_scaps[id] = pandoc.utils.stringify(val)
    end
  end

  local latex_meta = {}

  -- Get title from book metadata or top-level
  local title = nil
  if meta.book and meta.book.title then
    title = get_string(meta.book, "title")
  end
  if not title then
    title = get_string(meta, "title")
  end
  if title then
    table.insert(latex_meta, "\\title{" .. title .. "}")
  end

  -- Get author from book metadata or top-level
  local author = nil
  if meta.book and meta.book.author then
    author = get_string(meta.book, "author")
  end
  if not author then
    author = get_string(meta, "author")
  end
  if author then
    table.insert(latex_meta, "\\author{" .. author .. "}")
  end

  -- Get date from book metadata or top-level
  local date = nil
  if meta.book and meta.book.date then
    date = get_string(meta.book, "date")
  end
  if not date then
    date = get_string(meta, "date")
  end
  if date then
    table.insert(latex_meta, "\\date{" .. date .. "}")
  end

  -- Set Reed thesis-specific metadata commands
  local institution = get_string(meta, "institution")
  if institution then
    table.insert(latex_meta, "\\institution{" .. institution .. "}")
  end

  local division = get_string(meta, "division")
  if division then
    table.insert(latex_meta, "\\division{" .. division .. "}")
  end

  local department = get_string(meta, "department")
  if department then
    table.insert(latex_meta, "\\department{" .. department .. "}")
  end

  local advisor = get_string(meta, "advisor")
  if advisor then
    table.insert(latex_meta, "\\advisor{" .. advisor .. "}")
  end

  local altadvisor = get_string(meta, "altadvisor")
  if altadvisor then
    table.insert(latex_meta, "\\altadvisor{" .. altadvisor .. "}")
  end

  local degree = get_string(meta, "degree")
  if degree then
    table.insert(latex_meta, "\\degree{" .. degree .. "}")
  end

  -- Add to header-includes
  if #latex_meta > 0 then
    local latex_code = table.concat(latex_meta, "\n")
    local raw_block = pandoc.RawBlock("latex", latex_code)

    if meta["header-includes"] then
      if type(meta["header-includes"]) == "table" then
        table.insert(meta["header-includes"], raw_block)
      else
        meta["header-includes"] = {meta["header-includes"], raw_block}
      end
    else
      meta["header-includes"] = {raw_block}
    end
  end

  return meta
end

-- Apply a short caption string (plain text / markdown) to a Caption object.
local function apply_short_caption(caption, scap_str)
  local parsed = pandoc.read(scap_str, "markdown")
  if #parsed.blocks > 0 and parsed.blocks[1].content then
    caption.short = parsed.blocks[1].content
  else
    caption.short = { pandoc.Str(scap_str) }
  end
end

-- Check caption.long for a "||" separator.  If found, everything before "||"
-- becomes the figure caption and everything after becomes the LoF/LoT entry.
-- Returns the short caption string, or nil if no separator is present.
-- Also rewrites caption.long to remove the separator and the short part.
local function extract_separator_scap(caption)
  local full = pandoc.utils.stringify(caption.long)
  local sep = "||"
  local pos = full:find(sep, 1, true)
  if not pos then return nil end

  -- Trim whitespace around both parts
  local long_str  = full:sub(1, pos - 1):match("^%s*(.-)%s*$")
  local short_str = full:sub(pos + #sep):match("^%s*(.-)%s*$")

  if short_str == "" then return nil end

  -- Reparse the long part so formatting (math, italics) is preserved
  local long_parsed = pandoc.read(long_str, "markdown")
  if #long_parsed.blocks > 0 then
    caption.long = long_parsed.blocks
  end

  return short_str
end

-- Handle short captions for figures.
--
-- THREE ways to provide a short LoF entry (checked in this order):
--
-- 1. Separator in fig-cap (works for code chunks — recommended):
--      #| fig-cap: "Full caption here || Short LoF entry"
--
-- 2. Metadata table in _quarto.yml (also works for code chunks):
--      fig-scaps:
--        fig-my-label: "Short LoF entry"
--
-- 3. Inline attribute (Markdown images only):
--      ![Full caption](img.png){fig-scap="Short LoF entry"}
--
-- All three produce \caption[Short LoF entry]{Full caption} in LaTeX.
function Figure(fig)
  if not quarto.doc.is_format("pdf") then
    return fig
  end

  local scap = nil

  -- 1. || separator inside fig-cap
  scap = extract_separator_scap(fig.caption)

  -- 2. metadata lookup table (fig-scaps in _quarto.yml)
  if not scap then
    scap = fig_scaps[fig.identifier]
  end

  -- 3. inline attribute (Markdown images: ![...](img){fig-scap="..."})
  if not scap then
    scap = fig.attributes["fig-scap"]
    fig.attributes["fig-scap"] = nil
  end

  if scap and scap ~= "" then
    apply_short_caption(fig.caption, scap)
  end

  return fig
end

-- Handle short captions for tables.
--
-- Same three mechanisms as figures, using tbl-cap and tbl-scaps:
--   #| tbl-cap: "Full caption || Short LoT entry"
function Table(tbl)
  if not quarto.doc.is_format("pdf") then
    return tbl
  end

  local scap = nil

  scap = extract_separator_scap(tbl.caption)

  if not scap then
    scap = tbl_scaps[tbl.attr.identifier]
  end

  if not scap then
    scap = tbl.attr.attributes["tbl-scap"]
    tbl.attr.attributes["tbl-scap"] = nil
  end

  if scap and scap ~= "" then
    apply_short_caption(tbl.caption, scap)
  end

  return tbl
end

function Pandoc(doc)
  -- Only process for LaTeX/PDF output
  if not quarto.doc.is_format("pdf") then
    return doc
  end

  local meta = stored_meta or doc.meta

  -- Build front matter content in correct Reed College order:
  -- 1. Acknowledgements
  -- 2. Preface
  -- 3. List of Abbreviations (optional)
  -- 4. Table of Contents
  -- 5. List of Tables (optional)
  -- 6. List of Figures (optional)
  -- 7. Abstract
  -- 8. Dedication
  local frontmatter = {}

  -- 1. Acknowledgements
  local acknowledgements = get_string(meta, "thesis-acknowledgements")
  if acknowledgements then
    table.insert(frontmatter, "\\begin{acknowledgements}")
    table.insert(frontmatter, acknowledgements)
    table.insert(frontmatter, "\\end{acknowledgements}")
    table.insert(frontmatter, "")
  end

  -- 2. Preface
  local preface = get_string(meta, "thesis-preface")
  if preface then
    table.insert(frontmatter, "\\begin{preface}")
    table.insert(frontmatter, preface)
    table.insert(frontmatter, "\\end{preface}")
    table.insert(frontmatter, "")
  end

  -- 3. List of Abbreviations (optional, uses raw LaTeX content)
  local abbreviations = get_string(meta, "thesis-abbreviations")
  if abbreviations then
    table.insert(frontmatter, "\\chapter*{List of Abbreviations}")
    table.insert(frontmatter, abbreviations)
    table.insert(frontmatter, "\\clearpage")
    table.insert(frontmatter, "")
  end

  -- 4. Table of Contents (always included for thesis)
  -- Set \contentsname here (in the document body) rather than in the preamble.
  -- Quarto registers its own \AtBeginDocument hook that resets \contentsname to
  -- "Table of contents" (lowercase c) AFTER ours, so preamble-level fixes don't
  -- work. Setting it here, in the document body, runs after all AtBeginDocument
  -- hooks have fired and is therefore guaranteed to win.
  table.insert(frontmatter, "\\renewcommand{\\contentsname}{Table of Contents}")
  table.insert(frontmatter, "\\tableofcontents")
  table.insert(frontmatter, "")

  -- 5. List of Tables
  local lot = get_bool(meta, "thesis-lot")
  if lot then
    table.insert(frontmatter, "\\listoftables")
    table.insert(frontmatter, "")
  end

  -- 6. List of Figures
  local lof = get_bool(meta, "thesis-lof")
  if lof then
    table.insert(frontmatter, "\\listoffigures")
    table.insert(frontmatter, "")
  end

  -- 7. Abstract
  local abstract = get_string(meta, "thesis-abstract")
  if abstract then
    table.insert(frontmatter, "\\begin{abstract}")
    table.insert(frontmatter, abstract)
    table.insert(frontmatter, "\\end{abstract}")
    table.insert(frontmatter, "")
  end

  -- 8. Dedication
  local dedication = get_string(meta, "thesis-dedication")
  if dedication then
    table.insert(frontmatter, "\\begin{dedication}")
    table.insert(frontmatter, dedication)
    table.insert(frontmatter, "\\end{dedication}")
    table.insert(frontmatter, "")
  end

  -- Add mainmatter transition - THIS IS CRITICAL for chapter numbering
  table.insert(frontmatter, "\\mainmatter")
  table.insert(frontmatter, "\\pagestyle{fancyplain}")

  -- Insert front matter at the beginning of the document
  if #frontmatter > 0 then
    local frontmatter_code = table.concat(frontmatter, "\n")
    local frontmatter_block = pandoc.RawBlock("latex", frontmatter_code)
    table.insert(doc.blocks, 1, frontmatter_block)
  end

  return doc
end
