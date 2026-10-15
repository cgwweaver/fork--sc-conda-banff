# banff → conda-forge: findings & plan

Status: **scoping / info gathering**. Nothing built yet. Notes-only branch, not for upstream.

- Upstream: <https://github.com/StatCan/gensol-banff> (tag `3.1.3`)
- PyPI: <https://pypi.org/project/banff/> (3.1.3)
- Target: `recipes/banff/` in conda-forge/staged-recipes, maintainer `colin-ww` (+ upstream folks if they want)

---

## 1. Findings

### Source / distribution
- PyPI has **wheels only, no sdist**:
  - `banff-3.1.3-py3-none-manylinux…_x86_64.whl`
  - `banff-3.1.3-py3-none-win_amd64.whl`
- conda-forge builds from source, so the wheels are no use. `source:` = GitHub tag tarball
  `https://github.com/StatCan/gensol-banff/archive/refs/tags/3.1.3.tar.gz`
- Wheel tag `py3-none-<platform>`: C code is **not** a CPython extension. Probably shared libs loaded via ctypes/cffi → one build per platform, not per Python version (to confirm).
  - If true → can likely build once per OS, not once per Python version (cheaper, simpler).
- No macOS wheel upstream → macOS untested by upstream.

### Build system
- Top-level `Makefile` → `C/build/unix-like/Makefile` (C procs) → `Python/Makefile` (package).
- Windows: `build.cmd` + Visual Studio `.sln`/`.vcxproj` → separate build path from Linux.
- C procs built **twice: `STC_LANG=en` and `STC_LANG=fr`** (en/fr messages). Recipe must build both, or figure out what Python pkg expects.
- `Python/pyproject.toml` version string is `3.01.003` (zero-padded) vs tag/PyPI `3.1.3`. Need to check what version pip/conda sees after build.
- `Python/pyproject.toml` uses setuptools.

### Bundled C libraries (`C/libraries/_submodules/`)

| Dir | How bundled | On conda-forge? | Notes |
|---|---|---|---|
| `jansson` | real git submodule (akheron/jansson) | yes, `jansson` 2.15.1 | candidate to unbundle |
| `arrow-nanoarrow` | real git submodule (apache/arrow-nanoarrow) | yes, `libnanoarrow` 0.9.0 | candidate to unbundle; version match? |
| `stc-glpk` | **vendored copy** (plain dir, not submodule) | `glpk` 5.0 exists | "stc-" prefix → may be StatCan-modified. Must diff vs upstream GLPK 5.0 before unbundling |
| `STC_C_Libraries` | vendored (CommonAPI, IOUtilities, LPInterface) | n/a | StatCan's own code, stays bundled (fine) |

- **GitHub tag tarballs do NOT include submodule contents** → `jansson` + `nanoarrow` dirs will be empty. Options:
  1. Unbundle: use conda-forge `jansson` / `libnanoarrow` as `host` deps (preferred by conda-forge, needs Makefile patching).
  2. Multiple `source:` entries (tarballs of the pinned submodule commits) unpacked into those dirs. Allowed (conda-forge docs: multiple sources supported).
- conda-forge rule of thumb: "all dependencies have to be packaged by conda-forge as well" → reviewers will push for unbundling where practical.

### Runtime deps (from pyproject)

| Dep | banff pin | latest on conda-forge | Concern |
|---|---|---|---|
| python | >=3.10 | - | |
| pandas | >=2.0,<3 | - | pandas 3 out → upper pin will bite |
| pyarrow | >=14,<19 | **25.0.0** | **6 major versions behind** |
| nanoarrow (py) | >=0.5,<0.7 | 0.9.0 | behind |
| duckdb | >=0.7,<2 | 1.5.6 | ok for now |

### License
- GPL-3.0 (`LICENSE` at repo root). Fine for conda-forge. SPDX: `GPL-3.0-or-later` (classifier says "v3 or later") — confirm.
  - Bundled libs: jansson MIT, nanoarrow Apache-2.0, GLPK GPL-3.0 → list all license files in recipe.

### conda-forge & LLM-generated PRs
- No conda-forge-specific AI policy found (searched docs + web, Oct 2026). Other big projects (LLVM, Fedora, Rust) = "AI OK with human in the loop who's accountable + disclosure".
- **To do before submitting:** re-check conda-forge docs / Zulip / staged-recipes PR template for an AI policy.

### CI on the fork
- staged-recipes **builds run on conda-forge's Azure Pipelines** → do **not** run on `colin-ww` fork PRs. Only the GH Actions linter might.
- Can test on fork by adding own GH Actions workflow (fork-only, not copied upstream): `conda-build` / `rattler-build` on `ubuntu-latest`, `windows-latest`, `macos-latest`. Free on public repos.
- Locally (this cloud env): Linux x86_64 only.

---

## 2. Open questions

- [ ] How does Python pkg load the C procs? ctypes `.so`/`.dll`? → decides noarch-ish vs per-Python builds
- [ ] en + fr: both libs shipped in one package? (assume yes)
- [ ] `stc-glpk` modified vs upstream GLPK?
- [ ] Which nanoarrow C version does banff need vs conda-forge `libnanoarrow` 0.9?
- [ ] Does banff actually break with pyarrow >=19 / pandas 3, or are pins just "untested"? (ask upstream)
- [ ] Windows: VS/MSBuild path in conda-forge env feasible? macOS: does unix Makefile work with clang?
- [ ] Tests: ship `Python/tests` subset as recipe `test:` (import + a couple of procs)?

## 3. Plan

1. **Read** `Makefile`s (top, `C/build/unix-like`, `Python/`) + how Python loads C libs. No building.
2. **Check** stc-glpk diff vs GLPK 5.0; nanoarrow/jansson versions at pinned submodule commits.
3. **Contact upstream** (issue on StatCan/gensol-banff and/or email Banff Support `statcan.banff-banff.statcan@statcan.gc.ca`):
   - Interest in conda-forge? Want to be co-maintainers?
   - Would they publish an **sdist** to PyPI (incl. submodules)? Makes recipe much simpler.
   - Can pyarrow/pandas/nanoarrow upper pins be relaxed?
   - Any objection to unbundling jansson/nanoarrow/glpk?
4. **Decide maintainer role** (colin) — see §4.
5. Draft `recipes/banff/recipe.yaml` (v1 / rattler-build format; `example-v1` in this repo) on `claude/banff-conda-feedstock-9ueg9w`.
6. Test: Linux locally; Win/macOS via fork-only GH Actions workflow.
7. PR within `colin-ww/fork--sc-conda-banff` for review → colin copies to real staged-recipes PR, disclosing LLM assistance and requesting thorough review.

## 4. Maintainer responsibilities (decide before submitting)

Once merged, a `banff-feedstock` repo is created; maintainers get commit access. Work comes mostly via bot PRs:

- **Version bumps**: `regro-cf-autotick-bot` opens PR on new PyPI/GitHub release → check CI green, check deps changed, merge.
  - Wheel-only PyPI: bot may watch GitHub tags instead. Fine.
- **Migrations**: conda-forge rebuilds everything when e.g. new Python (3.15), new pyarrow/libarrow, new compilers → bot opens PR, maintainer merges if green.
- **Breakage**: when a migration fails (e.g. new Python version, compiler error, upstream pin conflict) → someone has to diagnose. This is where C build knowledge needed.
- **Issues** on feedstock from users.
- Realistic load: a few bot PRs/year, most "click merge". Occasional real fix. Upstream co-maintainers strongly reduce risk.
- Can step down later (open PR removing self from `recipe-maintainers`); conda-forge core can help orphaned feedstocks, but slowly.
