---
title: Documentation upkeep
permalink: /contributing/
---

# Documentation upkeep

The guide beside each module is the source of truth for that module's public behavior:

```text
modules/<name>/docs.md
local/<name>/docs.md
```

The Pages build collects those files into the site's `/reference/` section. Do not hand-copy a module guide into `docs/`; duplicate copies will drift.

## Documenting an API change

When a public function or contract changes:

1. Update the LuaLS declaration in `types.lua`.
2. Update the module's `docs.md` with its realm, signature, parameters, result shape, expected failures, lifecycle or ownership behavior, and a minimal example where usage is not obvious.
3. Update the matching smoke test in `test/smoke/`.
4. Add a new entry to `docs/_data/navigation.yml` if this is a new module.
5. Run `test/run.sh` and prepare the Pages source with `docs/build.sh`.

The API contract smoke test discovers normal `Kora.<module>.<function>` definitions and fails when their namespace or function is missing from `types.lua`, or when the exact symbol is absent from the adjacent guide.

## Previewing the source

Prepare the same source tree used by GitHub Actions:

```sh
./docs/build.sh .pages-source
```

The site itself is built by Jekyll through GitHub's supported Pages action. If Jekyll is available locally, build the prepared directory into `_site` and serve it with any static web server.

## Publishing

The `Publish documentation` workflow runs for documentation changes on `main` and can also be started manually. It:

1. collects every adjacent module guide;
2. builds the responsive Jekyll site;
3. uploads the Pages artifact; and
4. deploys it to the repository's `github-pages` environment.

In the repository settings, select **GitHub Actions** as the Pages source. The deployed site is expected at [qbcore2.github.io/kora_lib](https://qbcore2.github.io/kora_lib/).
