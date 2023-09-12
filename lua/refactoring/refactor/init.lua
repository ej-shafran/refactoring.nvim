local extract = require("refactoring.refactor.106")
local inline_func = require("refactoring.refactor.115")
local extract_var = require("refactoring.refactor.119")
local inline_var = require("refactoring.refactor.123")
local rename = require("refactoring.refactor.221")

local M = {}

-- TODO: Better Way?
-- First thought is to make extract a function that adds its functions to the M
-- object... not sure if I like that.
M.extract = extract.extract
M.extract_to_file = extract.extract_to_file
M.extract_block = extract.extract_block
M.extract_block_to_file = extract.extract_block_to_file
M.inline_func = inline_func.inline_func
M.extract_var = extract_var.extract_var
M.inline_var = inline_var.inline_var
M.rename = rename.rename

--- @type function
M[106] = extract.extract
--- @type function
M[115] = inline_func.inline_func
--- @type function
M[119] = extract_var.extract_var
--- @type function
M[123] = inline_var.inline_var

-- TODO: Perhaps I am really out thinking myself on this one.  But it seems way
-- nicer if we can query all the names of refactors that allow us to use fzf or
-- telescope for nice integration with refactor picking
M.refactor_names = {
    ["Inline Variable"] = "inline_var",
    ["Extract Variable"] = "extract_var",
    ["Extract Function"] = "extract",
    ["Extract Function To File"] = "extract_to_file",
    ["Extract Block"] = "extract_block",
    ["Extract Block To File"] = "extract_block_to_file",
    ["Inline Function"] = "inline_func",
    ["Rename"] = "rename",
}

return M
