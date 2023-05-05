local async = require("nio.tests")
local plugin = require("neotest-java")
local Tree = require("neotest.types").Tree
local Path = require("plenary.path")

local cwd = vim.loop.cwd()
local sep = Path.path.sep
local function path_join(...)
  return table.concat({ ... }, sep)
end

-- various paths
local function get_paths(data_dir)
  return {
    root = data_dir,
    single_test_file = path_join(data_dir, "src", "test", "java", "FileWithSingleTest.java"),
    multi_test_file = path_join(data_dir, "src", "test", "java", "FileWithTests.java"),
    subdir_test_file = path_join(data_dir, "src", "test", "java", "subdir", "FileWithTests.java"),
    subdir_other_test_file = path_join(
      data_dir,
      "src",
      "test",
      "java",
      "subdir",
      "AnotherFileWithTests.java"
    ),
    no_test_file = path_join(data_dir, "src", "test", "java", "FileWithoutTests.java"),
    src_file = path_join(data_dir, "src", "main", "java", "FileWithTests.java"),
    json_file = path_join(data_dir, "src", "test", "configFile.json"),
  }
end
local gradle_files = get_paths(path_join(cwd, "tests", "data", "gradle_project"))
local maven_files = get_paths(path_join(cwd, "tests", "data", "maven_project"))

describe("root", function()
  async.it("finds root dir correctly for Gradle project", function()
    assert.equals(gradle_files.root, plugin.root(gradle_files.multi_test_file))
  end)
  async.it("finds root dir correctly for Maven project", function()
    assert.equals(maven_files.root, plugin.root(maven_files.multi_test_file))
  end)
end)

describe("is_test_file", function()
  async.it("matches Java file with tests in them", function()
    assert.equals(true, plugin.is_test_file(gradle_files.multi_test_file))
  end)
  async.it("doesn't match Java file with no tests", function()
    assert.equals(false, plugin.is_test_file(gradle_files.no_test_file))
  end)
  async.it("doesn't match Java file not in 'test' directory", function()
    assert.equals(false, plugin.is_test_file(gradle_files.src_file))
  end)
  async.it("doesn't match non-Java file", function()
    assert.equals(false, plugin.is_test_file(gradle_files.json_file))
  end)
end)

describe("discover_positions", function()
  async.it("file with single test parsed correctly", function()
    local expected = {
      {
        id = gradle_files.single_test_file,
        name = "FileWithSingleTest.java",
        path = gradle_files.single_test_file,
        range = { 0, 0, 10, 0 },
        type = "file",
      },
      {
        {
          id = "FileWithSingleTest",
          name = "FileWithSingleTest",
          path = gradle_files.single_test_file,
          range = { 4, 0, 9, 1 },
          type = "namespace",
        },
        {
          {
            id = "FileWithSingleTest.passing_test",
            name = "passing_test",
            path = gradle_files.single_test_file,
            range = { 6, 31, 8, 5 },
            type = "test",
          },
        },
      },
    }
    local result = plugin.discover_positions(gradle_files.single_test_file):to_list()
    assert.are.same(expected, result)
  end)
  async.it("file with multiple test parsed correctly", function()
    local expected = {
      {
        id = gradle_files.multi_test_file,
        name = "FileWithTests.java",
        path = gradle_files.multi_test_file,
        range = { 0, 0, 15, 0 },
        type = "file",
      },
      {
        {
          id = "FileWithTests",
          name = "FileWithTests",
          path = gradle_files.multi_test_file,
          range = { 4, 0, 14, 1 },
          type = "namespace",
        },
        {
          {
            id = "FileWithTests.passing_test",
            name = "passing_test",
            path = gradle_files.multi_test_file,
            range = { 6, 31, 8, 5 },
            type = "test",
          },
        },
        {
          {
            id = "FileWithTests.failing_test",
            name = "failing_test",
            path = gradle_files.multi_test_file,
            range = { 11, 31, 13, 5 },
            type = "test",
          },
        },
      },
    }
    local result = plugin.discover_positions(gradle_files.multi_test_file):to_list()
    assert.are.same(expected, result)
  end)
  async.it("file in sub package parsed correctly", function()
    local expected = {
      {
        id = gradle_files.subdir_test_file,
        name = "FileWithTests.java",
        path = gradle_files.subdir_test_file,
        range = { 0, 0, 17, 0 },
        type = "file",
      },
      {
        {
          id = "subdir.FileWithTests",
          name = "subdir.FileWithTests",
          path = gradle_files.subdir_test_file,
          range = { 6, 0, 16, 1 },
          type = "namespace",
        },
        {
          {
            id = "subdir.FileWithTests.passing_test",
            name = "passing_test",
            path = gradle_files.subdir_test_file,
            range = { 8, 31, 10, 5 },
            type = "test",
          },
        },
        {
          {
            id = "subdir.FileWithTests.failing_test",
            name = "failing_test",
            path = gradle_files.subdir_test_file,
            range = { 13, 31, 15, 5 },
            type = "test",
          },
        },
      },
    }
    local result = plugin.discover_positions(gradle_files.subdir_test_file):to_list()
    assert.are.same(expected, result)
  end)
end)

-- not sure how to test build_spec
describe("build_spec", function()
  async.it("gradle - successful for single function", function()
    local tree = Tree.from_list({
      {
        id = "subdir.FileWithTests.passing_test",
        name = "passing_test",
        path = gradle_files.subdir_test_file,
        range = { 8, 31, 10, 5 },
        type = "test",
      },
    }, function(data)
      return data.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "gradle test --tests 'subdir.FileWithTests.passing_test'")
  end)
  async.it("gradle - successful on single namespace", function()
    local tree = Tree.from_list({
      {
        id = "subdir.FileWithTests",
        name = "subdir.FileWithTests",
        path = gradle_files.subdir_test_file,
        range = { 6, 0, 16, 1 },
        type = "namespace",
      },
      {
        {
          id = "subdir.FileWithTests.passing_test",
          name = "passing_test",
          path = gradle_files.subdir_test_file,
          range = { 8, 31, 10, 5 },
          type = "test",
        },
      },
      {
        {
          id = "subdir.FileWithTests.failing_test",
          name = "failing_test",
          path = gradle_files.subdir_test_file,
          range = { 13, 31, 15, 5 },
          type = "test",
        },
      },
    }, function(data)
      return data.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "gradle test --tests 'subdir.FileWithTests.*'")
  end)
  async.it("gradle - runs on entire file in subdir", function()
    local tree = Tree.from_list({
      {
        id = gradle_files.subdir_test_file,
        name = "FileWithTests.java",
        path = gradle_files.subdir_test_file,
        range = { 0, 0, 17, 0 },
        type = "file",
      },
      {
        {
          id = "subdir.FileWithTests",
          name = "subdir.FileWithTests",
          path = gradle_files.subdir_test_file,
          range = { 6, 0, 16, 1 },
          type = "namespace",
        },
        {
          {
            id = "subdir.FileWithTests.passing_test",
            name = "passing_test",
            path = gradle_files.subdir_test_file,
            range = { 8, 31, 10, 5 },
            type = "test",
          },
        },
        {
          {
            id = "subdir.FileWithTests.failing_test",
            name = "failing_test",
            path = gradle_files.subdir_test_file,
            range = { 13, 31, 15, 5 },
            type = "test",
          },
        },
      },
    }, function(x)
      return x.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "gradle test --tests 'subdir.FileWithTests.*'")
  end)
  async.it("gradle - runs on entire directory", function()
    local dir = path_join(gradle_files.root, "src", "test", "java", "subdir")
    local tree = Tree.from_list({
      {
        id = dir,
        name = dir,
        path = dir,
        type = "dir",
      },
      {
        {
          id = gradle_files.subdir_test_file,
          name = "FileWithTests.java",
          path = gradle_files.subdir_test_file,
          range = { 0, 0, 17, 0 },
          type = "file",
        },
        {
          {
            id = "subdir.FileWithTests",
            name = "subdir.FileWithTests",
            path = gradle_files.subdir_test_file,
            range = { 6, 0, 16, 1 },
            type = "namespace",
          },
          {
            {
              id = "subdir.FileWithTests.passing_test",
              name = "passing_test",
              path = gradle_files.subdir_test_file,
              range = { 8, 31, 10, 5 },
              type = "test",
            },
          },
          {
            {
              id = "subdir.FileWithTests.failing_test",
              name = "failing_test",
              path = gradle_files.subdir_test_file,
              range = { 13, 31, 15, 5 },
              type = "test",
            },
          },
        },
        {
          id = gradle_files.subdir_other_test_file,
          name = "AnotherFileWithTests.java",
          path = gradle_files.subdir_other_test_file,
          range = { 0, 0, 17, 0 },
          type = "file",
        },
        {
          {
            id = "subdir.AnotherFileWithTests",
            name = "subdir.AnotherFileWithTests",
            path = gradle_files.subdir_other_test_file,
            range = { 6, 0, 16, 1 },
            type = "namespace",
          },
          {
            {
              id = "subdir.AnotherFileWithTests.passing_test",
              name = "passing_test",
              path = gradle_files.subdir_other_test_file,
              range = { 8, 31, 10, 5 },
              type = "test",
            },
          },
          {
            {
              id = "subdir.AnotherFileWithTests.failing_test",
              name = "failing_test",
              path = gradle_files.subdir_other_test_file,
              range = { 13, 31, 15, 5 },
              type = "test",
            },
          },
        },
      },
    }, function(x)
      return x.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(
      spec.command,
      "gradle test --tests 'subdir.FileWithTests.*' --tests 'subdir.AnotherFileWithTests.*'"
    )
  end)
  async.it("maven - successful for single function", function()
    local tree = Tree.from_list({
      {
        id = "subdir.FileWithTests.passing_test",
        name = "passing_test",
        path = maven_files.subdir_test_file,
        range = { 8, 31, 10, 5 },
        type = "test",
      },
    }, function(data)
      return data.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "mvn Dtest=subdir.FileWithTests#passing_test test")
  end)
  async.it("maven - successful on single namespace", function()
    local tree = Tree.from_list({
      {
        id = "subdir.FileWithTests",
        name = "subdir.FileWithTests",
        path = maven_files.subdir_test_file,
        range = { 6, 0, 16, 1 },
        type = "namespace",
      },
      {
        {
          id = "subdir.FileWithTests.passing_test",
          name = "passing_test",
          path = maven_files.subdir_test_file,
          range = { 8, 31, 10, 5 },
          type = "test",
        },
      },
      {
        {
          id = "subdir.FileWithTests.failing_test",
          name = "failing_test",
          path = maven_files.subdir_test_file,
          range = { 13, 31, 15, 5 },
          type = "test",
        },
      },
    }, function(data)
      return data.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "mvn Dtest=subdir.FileWithTests test")
  end)
  async.it("maven - runs on entire file in subdir", function()
    local tree = Tree.from_list({
      {
        id = maven_files.subdir_test_file,
        name = "FileWithTests.java",
        path = maven_files.subdir_test_file,
        range = { 0, 0, 17, 0 },
        type = "file",
      },
      {
        {
          id = "subdir.FileWithTests",
          name = "subdir.FileWithTests",
          path = maven_files.subdir_test_file,
          range = { 6, 0, 16, 1 },
          type = "namespace",
        },
        {
          {
            id = "subdir.FileWithTests.passing_test",
            name = "passing_test",
            path = maven_files.subdir_test_file,
            range = { 8, 31, 10, 5 },
            type = "test",
          },
        },
        {
          {
            id = "subdir.FileWithTests.failing_test",
            name = "failing_test",
            path = maven_files.subdir_test_file,
            range = { 13, 31, 15, 5 },
            type = "test",
          },
        },
      },
    }, function(x)
      return x.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "mvn Dtest=subdir.FileWithTests test")
  end)
  async.it("maven - runs on entire directory", function()
    local dir = path_join(maven_files.root, "src", "test", "java", "subdir")
    local tree = Tree.from_list({
      {
        id = dir,
        name = dir,
        path = dir,
        type = "dir",
      },
      {
        {
          id = maven_files.subdir_test_file,
          name = "FileWithTests.java",
          path = maven_files.subdir_test_file,
          range = { 0, 0, 17, 0 },
          type = "file",
        },
        {
          {
            id = "subdir.FileWithTests",
            name = "subdir.FileWithTests",
            path = maven_files.subdir_test_file,
            range = { 6, 0, 16, 1 },
            type = "namespace",
          },
          {
            {
              id = "subdir.FileWithTests.passing_test",
              name = "passing_test",
              path = maven_files.subdir_test_file,
              range = { 8, 31, 10, 5 },
              type = "test",
            },
          },
          {
            {
              id = "subdir.FileWithTests.failing_test",
              name = "failing_test",
              path = maven_files.subdir_test_file,
              range = { 13, 31, 15, 5 },
              type = "test",
            },
          },
        },
        {
          id = maven_files.subdir_other_test_file,
          name = "AnotherFileWithTests.java",
          path = maven_files.subdir_other_test_file,
          range = { 0, 0, 17, 0 },
          type = "file",
        },
        {
          {
            id = "subdir.AnotherFileWithTests",
            name = "subdir.AnotherFileWithTests",
            path = maven_files.subdir_other_test_file,
            range = { 6, 0, 16, 1 },
            type = "namespace",
          },
          {
            {
              id = "subdir.AnotherFileWithTests.passing_test",
              name = "passing_test",
              path = maven_files.subdir_other_test_file,
              range = { 8, 31, 10, 5 },
              type = "test",
            },
          },
          {
            {
              id = "subdir.AnotherFileWithTests.failing_test",
              name = "failing_test",
              path = maven_files.subdir_other_test_file,
              range = { 13, 31, 15, 5 },
              type = "test",
            },
          },
        },
      },
    }, function(x)
      return x.id
    end)
    local spec = plugin.build_spec({ tree = tree })
    assert.equals(spec.command, "mvn Dtest=subdir.FileWithTests,subdir.AnotherFileWithTests test")
  end)
end)

describe("results", function()
  async.it("parses single-test test suite successfully", function()
    local spec = {
      cwd = path_join(cwd, "tests", "data", "xmls", "single_function"),
    }
    local result = plugin.results(spec, nil, nil)
    local passing = {}
    local failing = { "subdir.FileWithTests.failing_test" }
    for _, pass in pairs(passing) do
      assert.equals(result[pass].status, "passed")
      assert.equals(result[pass].short, nil)
    end
    for _, fail in pairs(failing) do
      assert.equals(result[fail].status, "failed")
      assert.equals(vim.startswith(result[fail].short, "java.lang.AssertionError"), true)
    end
  end)
  async.it("parses namespace test suite successfully", function()
    local spec = {
      cwd = path_join(cwd, "tests", "data", "xmls", "namespace"),
    }
    local result = plugin.results(spec, nil, nil)
    local passing = { "subdir.FileWithTests.passing_test" }
    local failing = { "subdir.FileWithTests.failing_test" }
    for _, pass in pairs(passing) do
      assert.equals(result[pass].status, "passed")
      assert.equals(result[pass].short, nil)
    end
    for _, fail in pairs(failing) do
      assert.equals(result[fail].status, "failed")
      assert.equals(vim.startswith(result[fail].short, "java.lang.AssertionError"), true)
    end
  end)
  async.it("parses file test suite successfully", function()
    local spec = {
      cwd = path_join(cwd, "tests", "data", "xmls", "file"),
    }
    local result = plugin.results(spec, nil, nil)
    local passing = { "subdir.FileWithTests.passing_test" }
    local failing = { "subdir.FileWithTests.failing_test" }
    for _, pass in pairs(passing) do
      assert.equals(result[pass].status, "passed")
      assert.equals(result[pass].short, nil)
    end
    for _, fail in pairs(failing) do
      assert.equals(result[fail].status, "failed")
      assert.equals(vim.startswith(result[fail].short, "java.lang.AssertionError"), true)
    end
  end)
  async.it("parses directory test suite successfully", function()
    local spec = {
      cwd = path_join(cwd, "tests", "data", "xmls", "dir"),
    }
    local result = plugin.results(spec, nil, nil)
    local passing =
      { "subdir.FileWithTests.passing_test", "subdir.AnotherFileWithTests.passing_test" }
    local failing =
      { "subdir.FileWithTests.failing_test", "subdir.AnotherFileWithTests.failing_test" }
    for _, pass in pairs(passing) do
      assert.equals(result[pass].status, "passed")
      assert.equals(result[pass].short, nil)
    end
    for _, fail in pairs(failing) do
      assert.equals(result[fail].status, "failed")
      assert.equals(vim.startswith(result[fail].short, "java.lang.AssertionError"), true)
    end
  end)
end)
