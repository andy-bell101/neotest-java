local lib = require("neotest.lib")
local xml = require("neotest.lib.xml")
local Path = require("plenary.path")
local scandir = require("plenary.scandir")
local logger = require("neotest.logging")

local context_manager = require("plenary.context_manager")
local open = context_manager.open
local with = context_manager.with

local package_query = vim.treesitter.query.parse(
  "java",
  [[
(package_declaration (identifier) @package.name)
]]
)

local M = { name = "neotest-java" }

--- Get the src/test directory relative to project root
-- @param path string
local function get_test_dir(path)
  return Path:new(M.root(path)) / "src" / "test"
end

--- Get the build/test-results/test directory relative to project root
-- @param path string
local function get_junit_dir(path)
  return Path:new(M.root(path)) / "build" / "test-results" / "test"
end

local function get_match_type(nodes)
  if nodes["test.name"] then
    return "test"
  elseif nodes["namespace.name"] then
    return "namespace"
  end
end

--- Determine which test runner to use (gradle or maven)
-- @param root plenary.Path
function determine_runner(root)
  local fallback = Settings.fallback_runner
  if Settings.force_runner then
    logger.info("Using enforced runner " .. Settings.force_runner)
    return Settings.force_runner
  end
  local gradle_file = (root / "build.gradle")
  local maven_file = (root / "pom.xml")
  local gradle_exists = gradle_file:exists()
  local maven_exists = maven_file:exists()
  if gradle_exists and maven_exists then
    logger.error(
      "could not uniquely determine build system, both pom.xml and build.gradle exist! Using fallback "
        .. fallback
    )
    return fallback
  elseif gradle_exists then
    logger.info("Found " .. gradle_file .. ", using gradle runner")
    return "gradle"
  elseif maven_exists then
    logger.info("Found " .. maven_file .. ", using maven runner")
    return "maven"
  else
    logger.error(
      "could not uniquely determine build system, neither pom.xml nor build.gradle exist at root location "
        .. root
        .. "! Using fallback "
        .. fallback
    )
    return fallback
  end
end

--- Construct the position for the captured match
-- @param file_path string
function M.build_position(file_path, source, captured_nodes)
  local match_type = get_match_type(captured_nodes)
  if match_type then
    ---@type string
    local name = vim.treesitter.get_node_text(captured_nodes[match_type .. ".name"], source)
    local definition = captured_nodes[match_type .. ".definition"]

    if match_type == "namespace" then
      local language_tree = vim.treesitter.get_string_parser(source, "java")
      local syntax_tree = language_tree:parse()
      local root = syntax_tree[1]:root()
      for _, captures, _ in package_query:iter_captures(root, source) do
        local package_name = vim.treesitter.get_node_text(captures, source)
        name = package_name .. "." .. name
      end
    end

    return {
      type = match_type,
      path = file_path,
      name = name,
      range = { definition:range() },
    }
  end
end

function M.position_id(position, namespaces)
  return table.concat(
    vim.tbl_flatten({
      vim.tbl_map(function(pos)
        return pos.name
      end, namespaces),
      position.name,
    }),
    "."
  )
end

-- Neotest interface funcs
M.root = lib.files.match_root_pattern("gradlew", "mvnw", "pom.xml", "build.gradle", ".git")

--- Figure out if given file is a test file
-- @param file_path string
function M.is_test_file(file_path)
  if not vim.endswith(file_path, ".java") then
    return false
  end
  local test_path = get_test_dir(file_path)
  for _, p in pairs(Path:new(file_path):parents()) do
    if tostring(p) == tostring(test_path) then
      return #M.discover_positions(file_path):to_list() ~= 1
    end
  end
  return false
end

--- Find all tests/namespaces in given file path
-- @param file_path string
function M.discover_positions(file_path)
  logger.info("Searching file " .. file_path .. " for test positions")
  local query = [[
    ((method_declaration
        (modifiers
            (marker_annotation name: (identifier) @marker)
            (#any-of? @marker "Test")
        )
        name: (identifier) @test.name
        body: (block) @test.definition))
    ((class_declaration name: (identifier) @namespace.name) @namespace.definition)
    ]]
  return lib.treesitter.parse_positions(file_path, query, {
    require_namespaces = true,
    position_id = "require('neotest-java').position_id",
    build_position = "require('neotest-java').build_position",
  })
end

--- Find all children with the matching type in tree
-- @param type string
-- @param type neotest.Tree
local function find_child_type_in_tree(type, tree)
  local children = {}
  for _, n in tree:iter_nodes() do
    local potential = n:data()
    if potential.type == type then
      table.insert(children, potential)
    end
  end
  return children
end

--- Determine the gradle arguments to use to run the given position
-- @param pos neotest.Position
-- @param tree neotest.Tree | nil
local function get_gradle_args_for_position(pos, tree)
  if pos.type == "test" then
    return { "--tests", "'" .. pos.id .. "'" }
  elseif pos.type == "namespace" then
    return { "--tests", "'" .. pos.id .. ".*'" }
  else
    -- file or dir
    local namespaces = find_child_type_in_tree("namespace", tree)
    local args = {}
    for _, n in pairs(namespaces) do
      table.insert(args, get_gradle_args_for_position(n, nil))
    end
    return vim.tbl_flatten(args)
  end
end

--- Determine the maven arguments to use to run the given position
-- @param pos neotest.Position
-- @param tree neotest.Tree | nil
local function get_maven_args_for_position(pos, tree)
  if pos.type == "test" then
    local elems = vim.split(pos.id, ".", true)
    local namespace = table.concat({ unpack(elems, 1, #elems - 1) }, ".")
    return { namespace .. "#" .. elems[#elems] }
  elseif pos.type == "namespace" then
    return { pos.id }
  else
    -- file or dir
    local namespaces = find_child_type_in_tree("namespace", tree)
    local args = {}
    for _, n in pairs(namespaces) do
      table.insert(args, get_maven_args_for_position(n, nil))
    end
    return vim.tbl_flatten(args)
  end
end

function M.build_spec(args)
  -- TODO: clear old build results. think that happens automatically though?
  logger.info("Building test spec")
  local tree = args.tree
  local position = tree:data()
  local command
  local runner = Settings.determine_runner(Path:new(M.root(position.path)))
  if runner == "gradle" then
    command = {
      "gradle",
      "test",
    }
    vim.list_extend(command, get_gradle_args_for_position(position, tree))
  elseif runner == "maven" then
    command = {
      "mvn",
    }
    local maven_args = get_maven_args_for_position(position, tree)
    local joined_args = "-Dtest=" .. table.concat(maven_args, ",")
    vim.list_extend(command, { "test", joined_args })
  end
  local output = {
    command = table.concat(command, " "),
    cwd = M.root(position.path),
    context = {},
  }
  logger.info("Test spec = " .. vim.inspect(output))
  return output
end

function M.results(spec, _, _)
  local results = {}
  local xml_files =
    scandir.scan_dir(tostring(get_junit_dir(spec.cwd)), { search_pattern = "%.xml$" })
  for _, file in pairs(xml_files) do
    logger.info("Pulling test results from Junit xml file " .. file)
    local data
    with(open(file, "r"), function(reader)
      data = reader:read("*a")
    end)

    local root = xml.parse(data)
    local testsuites
    if #root.testsuite == 0 then
      testsuites = { root.testsuite }
    else
      testsuites = root.testsuite
    end

    for _, testsuite in pairs(testsuites) do
      local testcases
      if #testsuite.testcase == 0 then
        testcases = { testsuite.testcase }
      else
        testcases = testsuite.testcase
      end

      for _, testcase in pairs(testcases) do
        local method_name = testcase._attr.name
        -- JUnit5 seems to output to the XML like "method_name()" instead of
        -- "method_name" like in JUnit 4, so we have to trim off the brackets
        if method_name:match("%(%)$") then
          method_name = method_name:sub(1, #method_name - 2)
        end
        local name = testsuite._attr.name .. "." .. method_name
        if testcase.failure then
          results[name] = {
            status = "failed",
            short = testcase.failure[1],
          }
        else
          results[name] = {
            status = "passed",
          }
        end
      end
    end
  end

  return results
end

Settings = {
  determine_runner = determine_runner,
  fallback_runner = "gradle",
  force_runner = nil,
}

-- https://stackoverflow.com/a/58795138
local function iscallable(x)
    if type(x) == 'function' then
        return true
    elseif type(x) == 'table' then
        local mt = getmetatable(x)
        return type(mt) == "table" and type(mt.__call) == "function"
    else
        return false
    end
end

setmetatable(M, {
  __call = function(_, opts)
    local setter = function(key, value)
      if value then
        if iscallable(value) then
          Settings[key] = value
        else
          Settings[key] = function()
            return value
          end
        end
      end
    end

    for k, v in pairs(opts) do
      setter(k, v)
    end
    return M
  end,
})
return M
