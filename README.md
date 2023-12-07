# neotest-java

> [!CAUTION]
> [This plugin is deprecated! Use this plugin instead!](https://github.com/rcasia/neotest-java)

[Neotest](https://github.com/rcarriga/neotest) adapter for Java using JUnit.
Compatible with Gradle and Maven projects.

Requires [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
and the parser for Java.

```lua
require("neotest").setup({
  adapters = {
    require("neotest-java")
  }
})
```

By default, the plugin determines whether you are in a Gradle or Maven project,
and runs the tests with the appropriate tool. You can customise which runner
to use with the following settings:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-java")({
        -- function to determine which runner to use based on project path
        determine_runner = function(project_root_path)
            -- return should be "maven" or "gradle"
            return "gradle"
        end,
        -- override the builtin runner discovery behaviour to always use given
        -- tool. Default is "nil", so no override
        force_runner = nil,
        -- if the automatic runner discovery can't uniquely determine whether
        -- to use Gradle or Maven, fallback to using this runner. Default is
        -- "gradle"
        fallback_runner = "gradle"
    })
  }
})
```

## Limitations

- For Gradle, so far only tested on toy projects from Exercism. Needs
  checking against a proper project.
- No "real" testing for Maven, since I don't know how it works. I have
  validated the generated commands against the Maven docs so they should be
  correct but I can't be sure.
