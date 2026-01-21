-- Lua filter to inject thesis metadata and front matter for Reed College thesis
-- This filter:
-- 1. Sets LaTeX metadata commands (title, author, date, institution, etc.) via header-includes
-- 2. Inserts front matter content directly into the document

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

-- Store metadata globally for use in Pandoc filter
local stored_meta = nil

function Meta(meta)
  -- Only process for LaTeX/PDF output
  if not quarto.doc.is_format("pdf") then
    return meta
  end

  stored_meta = meta

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

function Pandoc(doc)
  -- Only process for LaTeX/PDF output
  if not quarto.doc.is_format("pdf") then
    return doc
  end

  local meta = stored_meta or doc.meta

  -- Build front matter content in correct Reed College order
  local frontmatter = {}

  -- Acknowledgements
  local acknowledgements = get_string(meta, "thesis-acknowledgements")
  if acknowledgements then
    table.insert(frontmatter, "\\begin{acknowledgements}")
    table.insert(frontmatter, acknowledgements)
    table.insert(frontmatter, "\\end{acknowledgements}")
    table.insert(frontmatter, "")
  end

  -- Preface
  local preface = get_string(meta, "thesis-preface")
  if preface then
    table.insert(frontmatter, "\\begin{preface}")
    table.insert(frontmatter, preface)
    table.insert(frontmatter, "\\end{preface}")
    table.insert(frontmatter, "")
  end

  -- Table of Contents (always included for thesis)
  table.insert(frontmatter, "\\tableofcontents")
  table.insert(frontmatter, "")

  -- List of Tables
  local lot = get_bool(meta, "lot")
  if lot then
    table.insert(frontmatter, "\\listoftables")
    table.insert(frontmatter, "")
  end

  -- List of Figures
  local lof = get_bool(meta, "lof")
  if lof then
    table.insert(frontmatter, "\\listoffigures")
    table.insert(frontmatter, "")
  end

  -- Abstract
  local abstract = get_string(meta, "thesis-abstract")
  if abstract then
    table.insert(frontmatter, "\\begin{abstract}")
    table.insert(frontmatter, abstract)
    table.insert(frontmatter, "\\end{abstract}")
    table.insert(frontmatter, "")
  end

  -- Dedication
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
