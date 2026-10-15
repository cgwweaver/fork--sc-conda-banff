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
  - *Update (§7): no longer an issue for the recipe: jansson + nanoarrow now come from conda-forge, so the plain tag tarball is enough. An sdist would still help pip users.*
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
  - **Linux aarch64** (feedstock-only, later): ~~would probably work~~ *Correction (§8): would NOT work as-is: every Makefile hardcodes `-m64` (rejected by aarch64 GCC) and make_proc runs `ldd` (fails in cross builds). Needs patch changes; recipe skips `not (linux and x86_64)`.*
- **en/fr**: loader loads `lib<proc>_en.so` or `lib<proc>_fr.so` by language → recipe must build **both** (`make c_proc_en` + `make c_proc_fr`).
- **Charset blocker**: `C/build/unix-like/make_include/MakeDefaults` sets `-O3 -finput-charset=WINDOWS-1252 -fexec-charset=UTF-8`. **conda-forge GCC 14.4 and 15.3 are built without iconv** → `cc1: error: no iconv implementation, cannot convert from WINDOWS-1252 to UTF-8`. Ubuntu system GCC works (has iconv).
  - 37 non-GLPK C/H files contain non-ASCII (Latin-1/CP1252) bytes (French accents in messages).
  - **Fix in build.sh**: transcode compiled sources CP1252 → UTF-8 before `make`, then build with `-finput-charset=UTF-8`. Semantically identical to what upstream GCC does internally (it reads all as CP1252 and emits UTF-8).
  - Worth suggesting upstream: store sources as UTF-8 → flag not needed, any compiler works.
  - *Caveat (§8): if upstream does that, the recipe's transcode step must go. build.sh now stops with an error if `MakeDefaults` changes, and the French-message tests (`features/nls/test_nls.py`) catch garbled text.*
- **jansson Makefile runs `git submodule init`** during build → fails in a tarball build (no `.git`). Must bypass (link conda-forge `jansson` instead).
- **conda-forge libs available** (checked by installing): `jansson` 2.15.1 → `include/jansson.h`, `lib/libjansson.so.4`; `libnanoarrow` 0.9.0 → `include/nanoarrow/*.h`, `lib/libnanoarrow_shared.so`, `lib/libnanoarrow_static.a` (+ ipc), **not namespaced** (`NANOARROW_NAMESPACE` commented out).
- **Tools**: rattler-build 0.76.1, conda-smithy (linter), micromamba 2.x, all from conda-forge.

---

## 7. Recipe build & test results (2026-10-15)

Recipe: `recipes/banff/` on branch `claude/banff-conda-feedstock-9ueg9w` → **PR #2** (fork only). Files: `recipe.yaml`, `build.sh`, `check_procs.py`, `patches/0001-…patch`, `licenses/*`. Fork-only CI helper: `.github/workflows/banff-recipe-check.yml` (do **not** copy upstream).

### Result: ✅ builds + all tests pass, linux-64, Python 3.11 / 3.12 / 3.13

| Check | Result |
|---|---|
| Build (rattler-build 0.76.1, conda-forge pinning, gcc 15, sysroot 2.17) | py311 ✅ py312 ✅ py313 ✅, py314 skipped |
| `import banff` (+ io_util, nls, proc), `pip check` | ✅ |
| All 9 C procedures load, **en and fr** (`check_procs.py`) | ✅ 18 `.so` files |
| Upstream pytest quick set (`m_auto_pass`, minus SAS-data + fr_CA-locale tests) | ✅ **423 passed, 0 failed** |
| conda-smithy lint (`--conda-forge`) | ✅ except maintainer-exists check (GitHub API blocked in sandbox; fork CI runs it) |

### How the build works (plain words)
1. Download banff 3.1.3 source from the GitHub tag.
2. **Patch** the Makefiles: use conda's compiler/archiver/linker instead of hardcoded `gcc`/`ld`/`ar`; link conda-forge `jansson` + `libnanoarrow` instead of building the missing git submodules; drop a hardcoded `/usr/lib/gcc/x86_64-redhat-linux/8/` path.
3. `build.sh`: convert C sources CP1252 → UTF-8; run `make` once for English, once for French; `pip install` the Python package (with README/LICENSE copied in, like upstream CI does).
4. Tests run automatically after the build.

### New findings during the build

- **C23 / GCC 15**: GCC 15 defaults to C23 where `bool`/`false` are keywords → bundled GLPK 4.53 (`minisat.h: typedef int bool`) fails. Fix: `-std=gnu17` (what upstream's GCC 14 uses by default). Upstream should add this too, or their own build breaks when they move to GCC 15.
- **Asserts**: conda-forge `CPPFLAGS` contains `-DNDEBUG`, which would silently disable C `assert()`s that upstream keeps. Recipe deliberately leaves `CPPFLAGS` out.
- **Optimisation flags**: upstream `-O3`; recipe passes conda `CFLAGS` then `-O3` (last wins). conda's `-march=nocona` has no FMA → no fused multiply-add reordering, same as upstream's baseline x86-64.
- **French strings verified**: compared every non-ASCII string (French messages) in our 18 `.so` vs upstream's PyPI wheel → **all upstream messages present byte-identical** (UTF-8, e.g. "dû à une contrainte de cardinalité"). Differences only in machine code / string layout.
- **Test baseline**: upstream's own PyPI wheel, same env, same deps → fails the **same 18** tests our build fails without filters → failures are environmental, not ours:
  - 11 need `.sas7bdat` files generated by SAS (not in repo) — marker `m_sas_dataset` / `m_needs_sas_data`.
  - 1 needs the `fr_CA` OS locale (`test_numeric_locale`).
  - 6 are a **real upstream bug** ↓
- **🐛 Upstream bug: duckdb ≥1.4 breaks `exclude_where_*` options.** `processing.py:139` does `duckdb…arrow().num_rows`; since duckdb 1.4 `.arrow()` returns a `RecordBatchReader` (no `num_rows`) → `AttributeError`. Verified: duckdb 1.3.2 → pass, 1.4.4 → fail. Affects **pip users too** (upstream cap is `<2`).
  - ~~Recipe pins `duckdb >=0.7.0,<1.4`~~ *Update (§8): replaced by patch 0002 (`.arrow()` → `.to_arrow_table()` at 3 call sites in `processing.py`: lines 139, 154, 236) and upstream's `<2` bound restored. `to_arrow_table()` exists since duckdb 0.7.1; `fetch_arrow_table()` is deprecated in 1.5 and `.arrow().read_all()` breaks on 1.3, so neither of those works.*
  - **Report upstream** with the same 3-line diff (the PyPI wheel has the bug too; `remove_rows_where` with Arrow input also silently returns the wrong type).
- **🐛 Upstream bug: `import banff` crashes under `LC_ALL=C`** (`nls.py:124` calls `.lower()` on `None`, only `IndexError` caught). Doesn't hit the recipe tests, but worth reporting.
- **Python 3.14 skip**: caused by `pyarrow<19` and `nanoarrow<0.7` (no py3.14 builds on conda-forge); pandas<3 is fine, and duckdb is fine now that it's patched instead of pinned (python-duckdb for 3.14 starts at 1.4). conda-forge builds py3.11–3.14 (3.10 dropped).
- **Licenses**: bundled GLPK itself bundles AMD + COLAMD (LGPL-2.1-or-later), MiniSat (MIT), zlib 1.2.5 (Zlib), all statically linked, **with no license files in banff's repo**. Recipe declares `GPL-3.0-or-later AND LGPL-2.1-or-later AND MIT AND Zlib` and ships the texts in `recipes/banff/licenses/` (copied from GNU GLPK 4.53 tarball, identical to 5.0's).
- **GLPK fork detail**: ~10 files differ from pristine GLPK 4.53 (`glpk.h`, `env/env.c`, `glpapi06.c`, `proxy/*`, `cglib/cfg1.c`, `misc/keller.c`) and it re-adds the old `lpx` API → confirms it can't be swapped for conda-forge `glpk` 5.0.
- **Linking result**: our `.so` files need `libjansson.so.4` + `libnanoarrow_shared.so` from the env (rpath `$ORIGIN/…`), upstream's are fully static (only libc/libm). Fine for conda; that's the point of unbundling.
- **Parallel build caveat**: en and fr must run one after the other (shared GLPK object dir); within one language `-j` is safe.
- **conda (not conda-forge) AI policy** exists: "You are responsible for all of your contributions"; "Do not use AI agents … to submit your contributions or review PRs autonomously". conda-forge itself has none (checked docs, CFEPs, PR template, Oct 2026). → colin submits + answers reviews himself; disclose LLM help.

### nanoarrow: unbundled (as decided) — but reconsider?
Research agent recommends **keeping nanoarrow vendored at 0.6.0** instead:
- nanoarrow is explicitly "intended to be vendored"; conda-forge's own Python `nanoarrow` package vendors it.
- conda-forge `libnanoarrow` only exists as 0.9.0, unversioned SONAME, run_exports pin `>=0.9.0,<0.9.1` with no migrator. ~~→ every nanoarrow patch release needs a manual banff rebuild~~ *Correction (§8): not really. Nothing else on conda-forge depends on libnanoarrow, old builds stay on the channel, and a simulated 0.10 release still solves (picks 0.9.0). It only conflicts with a package that itself needs ≥0.10.*
- 0.6.0 = what upstream tested, and matches the Python `nanoarrow<0.7` cap.
- Cost: second `source:` (Apache tarball, sha256 `e4a02ac5…485d1`), a cmake step, C++ compiler in build, Apache-2.0 license files.
- Current recipe (unbundled) works and tests pass, so this is a judgement call → **decision for colin**.

### Still open
- [ ] Real sha256 of the GitHub tarball (fork CI job prints it; GitHub archive download is blocked in Claude's sandbox).
- [ ] Results of adversarial recipe review (4 lenses: conda-forge reviewer, build robustness, numerical fidelity vs upstream wheel, maintainability).
- [ ] nanoarrow vendored vs unbundled decision.
- [ ] Upstream contact (co-maintainer, sdist, duckdb bug, LC_ALL=C bug, gnu17, UTF-8 sources).

---

## 8. Adversarial review results (2026-10-15)

4 independent reviewer agents, each with one lens, then a skeptic agent per serious finding trying to refute it. **No blockers.** All scratch evidence/scripts: Claude's scratchpad `review/<lens>/` (session-local).

### Headline results
- **Fidelity: our build = upstream PyPI wheel, bit for bit.** About **3.1 million output cells compared, 0 differences** (float bit patterns, null masks, schemas), all 9 procedures:
  - upstream test suite (en + fr), all 15 `conversion_examples`, randomized float stress tests (N up to 5000, several seeds), edge-case params (1-ULP values, extreme seeds, 1e300);
  - random-seeded procs made reproducible by pinning `time()`; negative control (1-ULP change) was detected;
  - C console logs byte-identical in en and fr, except the "Created on <date>" line (build time).
  - Compiler check: no FMA, no AVX, no reassociated float reductions; same glibc math symbols; asserts on in both; no fast-math.
- **Build robustness: sound in conda-forge's CI image.** Toolchain reaches every sub-make, `-j` safe (also stress-tested with random make shuffle), exported symbols same as wheel, no undefined symbols, max glibc symbol 2.17, French strings byte-identical, GitHub tarball reproducible locally:
  `git archive --format=tar --prefix=gensol-banff-<v>/ <v> | gzip -n -6 | sha256sum` → gives GitHub's sha256 (handy for future version bumps).
- **conda-forge reviewer: would pass.** Lint clean (except sandbox-only maintainer check), license expression verified against symbols actually linked, GLPK vendoring reason holds, no existing banff on conda-forge/bioconda.
- **Maintainability: good shape.** Patch will likely apply to next release (patched Makefiles unchanged since 3.1.1). libnanoarrow: keep unbundled (simulated 0.10 release still solves). Upstream has had no commits since 2025-06-02; 2 dependabot PRs open (pyarrow<24, nanoarrow<0.9).

### Fixes applied (commit `f2298ec6` + `a2a9ad57`, PR #2)
| Finding | Severity (verified) | Fix |
|---|---|---|
| `duckdb <1.4` pin: blocks co-install with 11 conda-forge pkgs needing ≥1.4, also blocks py3.14 | **major** | patch 0002 `.arrow()` → `.to_arrow_table()` (3 sites), restore `<2`; tests now run with duckdb 1.5.6 |
| Recipe test shipped ~6 MB of upstream test data in every install | minor | only `Python/tests/**/*.py` + `pytest.ini` → package **4.5 MB → 2.1 MB** |
| `skip: not linux` didn't exclude aarch64/ppc64le | minor | `skip: not (linux and x86_64)` |
| AMD/COLAMD copyright + notice-retention terms not packaged | minor | added `licenses/AMD_README.txt`, `COLAMD_README.txt` (GLPK 4.53) |
| build.sh silently overrides upstream flags if they change | minor | guard: fail if `MakeDefaults` line differs |
| Empty submodule dirs on `-I` path could shadow conda headers | minor | `rmdir` guard |
| `CPPFLAGS` omission also drops `_FORTIFY_SOURCE` | minor | documented (upstream doesn't use it either) |
| PyPI `duckdb` = conda `python-duckdb` | minor | renamed run dep |
| `-W ignore::SyntaxWarning`, locale comment | minor | dropped / reworded |
| CRLF patch breaks if hand-edited | minor | recipe comment: regenerate with `git apply --3way` + `git diff` |
| Fork CI hid curl failures; Node 20 warning | minor | download-then-hash; checkout@v5 |

### Not applied (judgement calls, noted for later)
- **`-ffp-contract=off`**: no-op on linux-64 today (no FMA in `-march=nocona`); add if aarch64 is ever enabled (aarch64 has FMA → rounding would differ from upstream x86 wheel).
- **aarch64 support**: needs patch to drop `-m64` and make `ldd` non-fatal, plus cross-python. Skipped for now.
- **Link libnanoarrow statically** (`libnanoarrow_static.a`, like upstream): possible, avoids the exact-version run_export. Kept dynamic (conda-forge preference; no practical conflict today).
- **One Python-independent package instead of 3**: the C libs don't depend on Python; possible but unusual for reviewers.
- **build.sh re-run idempotency**: not an issue in CI (fresh source per variant).
- **Separate branch for the staged-recipes PR**: the fork-only workflow file must NOT go upstream → create the real PR from a fresh branch with only `recipes/banff/`:
  `git checkout -b banff upstream/main && git checkout claude/banff-conda-feedstock-9ueg9w -- recipes/banff`

### 🐛 More upstream bugs found (report to StatCan/gensol-banff)
1. **duckdb ≥1.4** breaks `exclude_where_*` (3-line fix = our patch 0002).
2. **French "BY variable not in data set" warning = format-string bug** → segfault (or GB-sized log) in French mode. `IO_Messages_fr.h:35` has `%8b.%*s` where English has `%*s`. Upstream wheel segfaults too (9 tests in fr mode). Not patched in recipe (parity with upstream); report upstream.
3. **`import banff` crashes under `LC_ALL=C`** (`nls.py:124`, `None.lower()`).
4. **GLPK 4.53 doesn't compile as C23** (GCC 15 default) → upstream needs `-std=gnu17` too.
5. (Typo) French message "dans lees équations".

### Top 5 things to watch as maintainer (plain words, from maintainability review)
1. **Bot PR fails with "Hunk FAILED"** → upstream changed a Makefile. Regenerate patch from a fresh checkout of the new tag with `git diff`; never hand-edit the `.patch` (hidden CRLF). If build.sh stops with "upstream MakeDefaults changed" → upstream changed flags/encoding; read it before changing anything.
2. **Every release**: compare `dependencies` in `Python/pyproject.toml` with the recipe `run:` list. If upstream raises pyarrow/nanoarrow caps → drop the py3.14 skip. If upstream fixes duckdb → drop patch 0002.
3. **duckdb**: getting the 3-line fix upstream is the most useful upstream contribution.
4. **libnanoarrow**: usually nothing to do. Only if a user can't install banff next to something needing newer libnanoarrow → bump `build.number` (rebuilds against newest). If that fails to compile → ask for help.
5. **Tests fail in a bot PR** → first run the same tests against upstream's PyPI wheel in an identical env. If the wheel fails too → upstream/environment problem, not the recipe.
