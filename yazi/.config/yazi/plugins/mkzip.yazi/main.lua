--- Zip the selected files (or the hovered one) into the current directory.
--- Asks for a name; an empty answer uses a default built from the contents:
---   one item   -> its name without extension   (report.pdf -> report.zip)
---   many items -> first name + count            (a.txt, b.txt, c.txt -> a-and-2-more.zip)

local M = {}

local state = ya.sync(function()
	local urls = {}
	for _, f in pairs(cx.active.selected) do
		urls[#urls + 1] = f.url
	end
	if #urls == 0 and cx.active.current.hovered then
		urls[1] = cx.active.current.hovered.url
	end
	return cx.active.current.cwd, urls
end)

local function notify(content, level)
	ya.notify { title = "Zip", content = content, timeout = 4, level = level or "info" }
end

local function base_name(url)
	local cha = fs.cha(url)
	-- Folders keep their full name; "my.project/" should not become "my".
	if cha and cha.is_dir then
		return url.name
	end
	return url.stem or url.name
end

local function default_name(urls)
	local first = base_name(urls[1])
	if #urls == 1 then
		return first
	end
	return string.format("%s-and-%d-more", first, #urls - 1)
end

-- report.zip -> report-1.zip -> report-2.zip ... so nothing is overwritten.
local function unique_target(cwd, stem)
	local target = cwd:join(stem .. ".zip")
	local n = 1
	while fs.cha(target) do
		target = cwd:join(string.format("%s-%d.zip", stem, n))
		n = n + 1
	end
	return target
end

function M:entry()
	ya.emit("escape", { visual = true })
	local cwd, urls = state()
	if #urls == 0 then
		return notify("Nothing to zip.", "warn")
	end

	local fallback = default_name(urls)
	local value, event = ya.input {
		pos = { "top-center", y = 2, w = 60 },
		title = string.format("Zip name (Enter = %s.zip):", fallback),
	}
	if event ~= 1 then
		return -- cancelled with Esc
	end

	local stem = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.[Zz][Ii][Pp]$", "")
	if stem == "" then
		stem = fallback
	end
	if stem:find("/", 1, true) then
		return notify("The name can't contain '/'.", "error")
	end
	local target = unique_target(cwd, stem)

	-- Items in the current folder are stored by name, so the zip has no
	-- leading directories; anything selected elsewhere keeps its full path.
	local args = { "-r", "-q", "-y", tostring(target), "--" }
	local cwd_str = tostring(cwd)
	for _, url in ipairs(urls) do
		args[#args + 1] = tostring(url.parent) == cwd_str and url.name or tostring(url)
	end

	notify(string.format("Zipping %d item%s...", #urls, #urls == 1 and "" or "s"))
	local output, err = Command("zip"):arg(args):cwd(cwd_str):stderr(Command.PIPED):output()
	if not output then
		return notify("Could not start zip: " .. tostring(err), "error")
	elseif not output.status.success then
		return notify("zip failed: " .. output.stderr, "error")
	end

	ya.emit("escape", { select = true })
	-- A plain string here: passing the Url object leaves the plugin task hanging.
	ya.emit("reveal", { tostring(target) })
	notify("Created " .. target.name)
end

return M
