local ls = require('luasnip')
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

local snippets = {
  s('upd', {
    t('UPDATE '),
    i(1, 'table_name'),
    t({ '', 'SET ' }),
    i(2, 'column'),
    t(' = '),
    i(3, 'value'),
    t({ '', 'WHERE ' }),
    i(4, 'condition'),
    t(';'),
    i(0),
  }),
}

-- Add to sql filetype
ls.add_snippets('sql', snippets)

-- Add to files with no extension (empty filetype)
ls.add_snippets('', snippets)
