# belikebee-claude-plugin

Claude Code marketplace with one plugin, `belikebee`: the feature workflow for the BeLikeBee repo (Next.js modular monolith, see its `ARCHITECTURE.md`). The content assumes that repo's layout (`src/modules/<name>/`, `.claude/rules/<name>.md`, Vitest + Playwright), so it is not meant for other projects. Full description: [plugins/belikebee/README.md](plugins/belikebee/README.md).

| Component | What it does |
| --- | --- |
| `/belikebee:feature-plan` | Plans a feature before code: sync check, docs and module rules, open decisions, plan with verify checks. Starts `pattern-scout` first. |
| `/belikebee:feature-scaffold` | Implements an agreed feature test-first inside its module. |
| `/belikebee:feature-tests` | Adds unit, integration or E2E tests and proves each suite can fail. |
| `/belikebee:feature-ship` | Turns the working tree into one clean commit on `dev` and appends the `LOG.md` line. |
| `belikebee:pattern-scout` agent | Read-only search for code and conventions a new feature should reuse or copy. |
| PreToolUse hook (Edit, Write, MultiEdit) | Blocks imports that break the module boundaries. Needs `bash` and `jq`. |

## Install

The BeLikeBee repo enables it in `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`), so Claude Code offers to install it when the repo is opened. By hand:

```text
/plugin marketplace add ivanlysakov/belikebee-claude-plugin
/plugin install belikebee@belikebee-plugins
```

Check the manifests with `claude plugin validate .` and `claude plugin validate plugins/belikebee`.
