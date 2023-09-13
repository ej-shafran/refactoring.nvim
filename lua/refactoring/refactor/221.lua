local Region = require("refactoring.region")
local get_input = require("refactoring.get_input")
local Pipeline = require("refactoring.pipeline")
local selection_setup = require("refactoring.tasks.selection_setup")
local refactor_setup = require("refactoring.tasks.refactor_setup")
local post_refactor = require("refactoring.tasks.post_refactor")
local ensure_code_gen = require("refactoring.tasks.ensure_code_gen")
local lsp_utils = require("refactoring.lsp_utils")
local ts_locals = require("refactoring.ts-locals")
local get_select_input = require("refactoring.get_select_input")
local utils = require("refactoring.utils")

local M = {}

---@param new_name string
---@param new_value string
---@param identifiers TSNode[]
---@param values TSNode[]
---@param identifier_to_exclude TSNode[]
---@param bufnr integer
---@return string[] new_identifiers
---@return string[] new_values
local function multiple_variable_declaration(
    new_name,
    new_value,
    identifiers,
    values,
    identifier_to_exclude,
    bufnr
)
    local new_identifiers, new_values = {}, {}

    for idx, identifier in pairs(identifiers) do
        if identifier ~= identifier_to_exclude then
            table.insert(
                new_identifiers,
                vim.treesitter.get_node_text(identifier, bufnr)
            )
            table.insert(
                new_values,
                vim.treesitter.get_node_text(values[idx], bufnr)
            )
        else
            table.insert(new_identifiers, new_name)
            table.insert(new_values, new_value)
        end
    end

    return new_identifiers, new_values
end

---@param identifiers TSNode[]
---@param bufnr integer
---@return TSNode|nil, integer|nil
local function get_node_to_rename(identifiers, bufnr)
    --- @type TSNode|nil, integer|nil
    local node_to_rename, identifier_pos

    if #identifiers == 1 then
        identifier_pos = 1
        node_to_rename = identifiers[identifier_pos]
    else
        node_to_rename, identifier_pos = get_select_input(
            identifiers,
            "221: Select an identifier to rename:",
            ---@param node TSNode
            ---@return string
            function(node)
                return vim.treesitter.get_node_text(node, bufnr)
            end
        )
    end

    return node_to_rename, identifier_pos
end

---@param declarator_node TSNode
---@param node_to_rename TSNode
---@param refactor Refactor
local function get_declaration_type(declarator_node, node_to_rename, refactor)
    if not refactor.ts:has_types() then
        return nil
    end

    local all_types = refactor.ts:get_local_types(declarator_node)

    local old_name =
        utils.trim(vim.treesitter.get_node_text(node_to_rename, refactor.bufnr)) --[[@as string]]

    if old_name == nil then
        -- just get the first key, there's probably multiple declarations
        for key, _ in pairs(all_types) do
            old_name = key
            break
        end
    end

    local type = all_types[old_name]

    return type
end

---@param declarator_node TSNode
---@param identifiers TSNode[]
---@param node_to_rename TSNode
---@param new_name string
---@param refactor Refactor
---@param definition TSNode[]
---@param identifier_pos integer
---@return LspTextEdit[]
local function rename_variable_text_edits(
    declarator_node,
    identifiers,
    node_to_rename,
    new_name,
    refactor,
    definition,
    identifier_pos
)
    local text_edits = {}

    local references =
        ts_locals.find_usages(definition, refactor.scope, refactor.bufnr)

    local all_values = refactor.ts:get_local_var_values(declarator_node)

    -- account for python giving multiple results for the values query
    if refactor.filetype == "python" then
        if #identifiers > 1 then
            all_values[#all_values] = nil
        else
            all_values = { all_values[#all_values] }
        end
    end

    local type = get_declaration_type(declarator_node, node_to_rename, refactor)

    local value_node_to_rename = all_values[identifier_pos]
    local new_value =
        vim.treesitter.get_node_text(value_node_to_rename, refactor.bufnr)

    local is_mut = refactor.ts.is_mut(
        vim.treesitter.get_node_text(declarator_node, refactor.bufnr)
    )

    if #identifiers == 1 then
        local new_string = refactor.code.variable({
            name = new_name,
            value = new_value,
            is_mut = is_mut,
            type = type,
        })
        table.insert(
            text_edits,
            lsp_utils.replace_text(
                Region:from_node(declarator_node, refactor.bufnr),
                utils.trim(new_string) --[[@as string]]
            )
        )
    else
        local new_identifiers, new_values = multiple_variable_declaration(
            new_name,
            new_value,
            identifiers,
            all_values,
            node_to_rename,
            refactor.bufnr
        )

        table.insert(
            text_edits,
            lsp_utils.replace_text(
                Region:from_node(declarator_node, refactor.bufnr),
                utils.trim(refactor.code.variable({
                    multiple = true,
                    identifiers = new_identifiers,
                    values = new_values,
                    type = type,
                    is_mut = is_mut,
                })) --[[@as string]]
            )
        )
    end

    for _, ref in pairs(references) do
        --- @type TSNode
        local parent = ref:parent()
        if refactor.ts.should_check_parent_node(parent:type()) then
            ref = parent
        end

        table.insert(
            text_edits,
            lsp_utils.replace_text(Region:from_node(ref), new_name)
        )
    end
    return text_edits
end

---@param renaming "function"|"variable"
---@param declarator_node TSNode
---@param identifiers TSNode[]
---@param node_to_rename TSNode
---@param new_name string
---@param refactor Refactor
---@param definition TSNode[]
---@param identifier_pos integer
---@return LspTextEdit[]
local function rename_text_edits(
    renaming,
    declarator_node,
    identifiers,
    node_to_rename,
    new_name,
    refactor,
    definition,
    identifier_pos
)
    if renaming == "variable" then
        return rename_variable_text_edits(
            declarator_node,
            identifiers,
            node_to_rename,
            new_name,
            refactor,
            definition,
            identifier_pos
        )
    else
        return {}
    end
end

---@param refactor Refactor
---@param declarator TSNode
---@param renaming "function"|"variable"
---@return TSNode[]
local function get_identifiers(refactor, declarator, renaming)
    if renaming == "variable" then
        return refactor.ts:get_local_var_names(declarator)
    else
        return {}
    end
end


---@param refactor Refactor
---@return TSNode|nil declarator_node
---@return "function"|"variable"|nil renaming
local function get_declarator_node(refactor)
    --- @type "function"|"variable"
    local renaming = "variable"
    --- @type TSNode|nil
    local declarator_node = refactor.ts:local_declarations_in_region(
        refactor.scope,
        refactor.region
    )[1]

    if declarator_node == nil then
        -- if the visual selection does not contain a declaration and it only contains a reference
        -- (which is under the cursor)
        local identifier_node = vim.treesitter.get_node()
        if identifier_node == nil then
            return nil, nil
        end
        local definition =
            ts_locals.find_definition(identifier_node, refactor.bufnr)
        declarator_node =
            refactor.ts.get_container(definition, refactor.ts.variable_scope)

        if declarator_node == nil then
            renaming = "function"
            declarator_node =
                ts_locals.containing_scope(definition, refactor.bufnr, false)
        end
    end

    return declarator_node, renaming
end

---@param refactor Refactor
---@return boolean, Refactor|string
local function rename_setup(refactor)
    local declarator_node, renaming = get_declarator_node(refactor)

    if declarator_node == nil or renaming == nil then
        return false, "Couldn't determine declarator node"
    end

    local identifiers = get_identifiers(refactor, declarator_node, renaming)

    if #identifiers == 0 then
        return false, "No declarations in selected area"
    end

    local node_to_rename, identifier_pos =
        get_node_to_rename(identifiers, refactor.bufnr)

    if node_to_rename == nil or identifier_pos == nil then
        return false, "Couldn't determine node to rename"
    end

    local definition = ts_locals.find_definition(node_to_rename, refactor.bufnr)

    local new_name = get_input("221: new name > ")
    if not new_name or new_name == "" then
        return false, "221: must have a new name"
    end

    local text_edits = rename_text_edits(
        renaming,
        declarator_node,
        identifiers,
        node_to_rename,
        new_name,
        refactor,
        definition,
        identifier_pos
    )

    refactor.text_edits = text_edits
    return true, refactor
end

---@param refactor Refactor
local function ensure_code_gen_221(refactor)
    local list = { "variable" }

    return ensure_code_gen(refactor, list)
end

---@param bufnr integer
---@param config Config
function M.rename(bufnr, config)
    Pipeline:from_task(refactor_setup(bufnr, config))
        :add_task(ensure_code_gen_221)
        :add_task(selection_setup)
        :add_task(rename_setup)
        :after(post_refactor.post_refactor)
        :run(nil, vim.notify)
end

return M
