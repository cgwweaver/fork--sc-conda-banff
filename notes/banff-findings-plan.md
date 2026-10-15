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
| `stc-glpk` | **vendored copy** (plain dir, not submodule) | `glpk` 5.0 exists | **GLPK 4.53 (2014)**, flattened dir layout + `STC_GLPK_ONEDIR` ifdefs (build tweaks). 66 files differ vs 5.0. See §5 Q5 |
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
- [x] `stc-glpk` modified vs upstream GLPK? → it's 4.53 + StatCan build ifdefs; diff vs pristine 4.53 still TBD
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

---

## 5. Questions for upstream: context, pros/cons

Six questions. Ordered by how much they change the recipe.
"Our preferred answer" = what makes the recipe simplest / most likely to be accepted.

### Q1. Do they want banff on conda-forge at all?

- **Why ask**: it's their software. Packaging without asking is allowed (GPL), but rude, and conda-forge reviewers often ask "is upstream aware?".
- **Pros for them**:
  - `conda install banff` for users in conda/mamba/pixi envs (common in gov/academia, incl. StatCan's own Jupyter/Kubeflow envs, via Artifactory conda mirrors).
  - conda solver handles pyarrow/pandas/duckdb compat properly, no pip+conda mixing.
  - Free multi-OS build CI they don't have to run (incl. macOS, which they don't ship today).
  - Their C libs get rebuilt automatically for new Pythons/compilers.
- **Cons for them**:
  - Another channel where users file bugs ("conda version broken").
  - Versions on conda may lag PyPI by days (bot PR → merge).
  - Their pins (pyarrow<19 etc.) become visible pain → pressure to relax.
  - Possible StatCan policy angle: is publishing on a 3rd-party channel OK officially? (Probably fine: it's already public on PyPI/GitHub under GPL.)
- **If "no"**: we can still do it, but I'd reconsider. Without upstream buy-in, every break lands on you.

### Q2. Will someone upstream co-maintain the feedstock?

- **What it means**: their GitHub username in `recipe-maintainers` → write access to `banff-feedstock`, pinged on bot PRs/issues. No obligation to *do* anything; just able to.
- **Pros**:
  - They know the C build. When a compiler/Python bump breaks it, they fix in minutes what would take you (+LLM) hours.
  - They can merge version bumps right after releasing → no lag.
  - Reviewers trust a recipe with upstream maintainers much more → faster acceptance. Strongly helps the "LLM-assisted PR" concern.
- **Cons**:
  - Their time; GitHub notifications.
  - Possibly needs manager OK at StatCan (time on external project).
- **Middle ground**: listed as maintainer but "best effort", you handle routine merges. Very common.

### Q3. Would they publish an sdist (source tarball) on PyPI?

- **Background**: PyPI currently has only built wheels. An sdist = `banff-3.1.3.tar.gz` with full source. `python -m build --sdist`, ~one line in their release workflow.
- **Why it matters**:
  - GitHub tag tarball **omits git submodules** (jansson, nanoarrow) → recipe needs 3 `source:` entries pinned to exact submodule commits, and must be updated by hand every time they bump a submodule. Bot can't do that.
  - An sdist that includes submodule contents → single source, bot auto-updates cleanly.
  - Also helps pip users on platforms without a wheel (macOS, Linux ARM): pip can build from source.
- **Pros**: simpler recipe, less maintenance, smoother bot bumps, benefits pip users too.
- **Cons for them**: sdist must actually build from scratch (needs `MANIFEST.in`/build to include C sources + submodules). Current build is Makefile → setuptools, so may need some work. Possible sdist build failures reported by pip users.
- **If "no"**: workable, just more manual. (Alternative: if they unbundle per Q5 for jansson/nanoarrow, submodules no longer matter, GitHub tarball is enough.)

### Q4. Can the upper pins be relaxed? (pyarrow<19, pandas<3, nanoarrow<0.7)

- **Background**: conda-forge currently has pyarrow 25, pandas 3.x, nanoarrow 0.9.
- **Why it matters**:
  - Environment conflicts: banff forces pyarrow ≤18 → can't coexist with anything needing newer pyarrow (e.g. recent polars/duckdb/geopandas versions over time). Users get "unsolvable" or silent downgrades.
  - New Pythons: old pyarrow builds don't exist for new Python versions (likely 3.14+) → banff uninstallable there; recipe test fails when conda-forge adds a new Python.
- **Key sub-question**: *real breakage or just untested?* Pyproject comments say: pandas 3 "untested", nanoarrow "adjust for each release". If untested → ask them to run their test suite against latest and bump.
- **Options**:
  - Upstream relaxes pins in a new release (best).
  - conda-forge recipe loosens pins itself (allowed, common, but risky: we ship combinations upstream never tested; needs tests in recipe to catch breaks).
  - Keep pins (simplest, but install conflicts grow over time).
- **Pros of relaxing**: works in modern envs, new Pythons. **Cons**: possible real bugs with new pyarrow/pandas (pandas 3 had big changes: copy-on-write, string dtype) → statistical output risk. For an official StatCan tool, they may (reasonably) be conservative.

### Q5. Any objection to using conda-forge's jansson / nanoarrow / GLPK instead of bundled copies?

- **Background**: conda-forge prefers "unbundling": link against shared conda-forge libs instead of compiling private copies. Reviewers usually ask.
- **Per library**:

| Lib | Bundled | conda-forge | Verdict |
|---|---|---|---|
| jansson (JSON) | git submodule, some commit | 2.15.1 | **unbundle likely fine**: stable C API, low risk |
| nanoarrow C (Arrow C data) | git submodule, some commit | libnanoarrow 0.9.0 | **probably fine**, but nanoarrow still pre-1.0 → API changes between versions; check which version banff uses |
| GLPK (LP solver) | **4.53 from 2014**, StatCan tweaks | 5.0 | **keep bundled** (see below) |

- **GLPK, why keep bundled**:
  - 4.53 → 5.0 = 7 years of changes; 5.0 removed deprecated APIs → banff may not compile against it.
  - LP solver version changes can change **numerical results** (different pivoting / tie-breaking → different but equally-optimal solutions). Banff uses LP for error localization (Errorloc) → different imputation results. For official statistics, reproducibility vs. the PyPI/SAS version matters a lot.
  - conda-forge accepts bundling when justified ("patched/old version required, results must match upstream"). Document it in recipe comments + license file.
- **Pros of unbundling**: smaller pkg, security/bug fixes via shared libs, reviewer-happy, removes submodule problem (Q3) entirely.
- **Cons**: Makefile patches (we maintain those patches, they can break on every banff release), risk of behaviour differences, testing burden.
- **Ask upstream**: are jansson/nanoarrow versions pinned for a reason? Would they accept a Makefile option like `USE_SYSTEM_JANSSON=1` upstream (so conda doesn't carry patches)?

### Q6. Linux/macOS/Windows build support: will they help / accept patches?

- **Background**: Linux = Makefile, Windows = Visual Studio `.sln` (not used by conda-forge's normal toolchain easily), macOS = never built by upstream.
- **Why it matters**: conda-forge expects all OSes unless skipped with a reason.
- **Ask**:
  - Has anyone built on macOS? Known issues?
  - Would they accept small portability patches upstream (e.g. Makefile honouring `$CC`/`$CFLAGS`/`$PREFIX`, clang fixes)?
  - Windows: OK to build via MSBuild in conda env, or would they consider CMake long-term? (Don't push CMake; just ask.)
- **Pros of upstreaming patches**: recipe stays clean, no carried patches. **Cons**: their review time; release cycle delays.
- **Fallback**: start Linux(+macOS if easy), `skip: win` with comment, add Windows later.

### Suggested message structure (email / GitHub issue)
1. Who you are (StatCan colleague / user), what you want (conda-forge package), that it's a volunteer side effort.
2. Transparency: recipe drafted with LLM (Claude Code) help; you're not a C build expert; want their input.
3. Q1 + Q2 (yes/no-ish), then Q3–Q6 (technical, can answer later or async).
4. Link to draft recipe once it exists.
- Channel: GitHub issue on StatCan/gensol-banff (public, discoverable) **or** email Banff Support (`statcan.banff-banff.statcan@statcan.gc.ca`). As a StatCan employee, maybe internal email/Teams first, then public issue.

---

## 6. Build-attempt findings (2026-10-15)

Decisions assumed for first recipe attempt (conservative): **keep upstream dep caps**, **no PyPI sdist → GitHub tag tarball**, **only GLPK (+ StatCan's own STC libs) bundled**, jansson + nanoarrow from conda-forge.

- **Tag vs main**: `main` is 1 commit past `3.1.3` (FR release notes only). Recipe builds the tag.
- **GitHub tarball download blocked in Claude's cloud env** (proxy 403 on archive/codeload for this repo; `git clone` works). Local tests use `git archive` of tag `3.1.3` → identical file contents, but **sha256 of GitHub's real tarball must be confirmed elsewhere** (fork GH Actions or colin locally: `curl -L <url> | sha256sum`).
- **Platforms**:
  - **macOS: skip.** `Python/src/banff/_common/src/proc/loader.py` only handles `Windows` and `Linux` (`platform.system()`), path hardcoded `bin/<linux|windows>/x64/`. No darwin branch → upstream limitation, valid skip reason.
  - **Windows: skip initially.** Build is Visual Studio `.sln`/`.vcxproj` + `build.cmd`, separate from the Makefile path. Follow-up.
  - **Linux aarch64** (feedstock-only, later): loader path says `x64` but it's just a dir name → would probably work. Not now.
- **en/fr**: loader loads `lib<proc>_en.so` or `lib<proc>_fr.so` by language → recipe must build **both** (`make c_proc_en` + `make c_proc_fr`).
- **Charset blocker**: `C/build/unix-like/make_include/MakeDefaults` sets `-O3 -finput-charset=WINDOWS-1252 -fexec-charset=UTF-8`. **conda-forge GCC 14.4 and 15.3 are built without iconv** → `cc1: error: no iconv implementation, cannot convert from WINDOWS-1252 to UTF-8`. Ubuntu system GCC works (has iconv).
  - 37 non-GLPK C/H files contain non-ASCII (Latin-1/CP1252) bytes (French accents in messages).
  - **Fix in build.sh**: transcode compiled sources CP1252 → UTF-8 before `make`, then build with `-finput-charset=UTF-8`. Semantically identical to what upstream GCC does internally (it reads all as CP1252 and emits UTF-8).
  - Worth suggesting upstream: store sources as UTF-8 → flag not needed, any compiler works.
- **jansson Makefile runs `git submodule init`** during build → fails in a tarball build (no `.git`). Must bypass (link conda-forge `jansson` instead).
- **conda-forge libs available** (checked by installing): `jansson` 2.15.1 → `include/jansson.h`, `lib/libjansson.so.4`; `libnanoarrow` 0.9.0 → `include/nanoarrow/*.h`, `lib/libnanoarrow_shared.so`, `lib/libnanoarrow_static.a` (+ ipc), **not namespaced** (`NANOARROW_NAMESPACE` commented out).
- **Tools**: rattler-build 0.76.1, conda-smithy (linter), micromamba 2.x, all from conda-forge.
