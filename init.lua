local fmt = require("format")

-- vim.cmd("edit rustfmt/small.rs")
-- fmt(vim.api.nvim_get_current_buf(), {
--     cmd = "rustfmt",
--     args = { "--edition", "2021", "--emit", "stdout" },
--     stdin = true,
-- })

vim.cmd("edit prettier/big.js")
fmt(vim.api.nvim_get_current_buf(), {
    cmd = "prettier",
    args = { "--stdin-filepath" },
    fname = true,
    stdin = true,
})
