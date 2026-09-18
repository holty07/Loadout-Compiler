# Setup guide

Bootstrapping **Loadout Compiler** from an empty GitHub repo to a green CI build.
Everything here is M0. Nothing in this guide implements a game rule.

---

## 1. Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Godot | 4.7 stable | Standard build, not Mono |
| Git | any recent | — |
| Python | 3.11+ | Only for the sweep fan-out script |
| Android SDK + JDK 17 | — | Deferred until M5; not needed to start |
| Xcode | — | Deferred until M5; macOS only |

On CachyOS, Godot from the repos or as a downloaded binary both work. Keep the exact
version string handy — CI must pin the same build, because a Godot version change can
alter behaviour and will show up as a determinism failure that looks like a code bug.

```bash
godot --version   # record this in .godot-version
```

---

## 2. Repo bootstrap

Clone with `gh` so it uses whichever protocol your `gh auth login` already configured:

```bash
gh repo clone holty07/loadout-compiler
cd loadout-compiler
```

`gh auth login` sets up HTTPS credentials by default. If you want SSH instead, set it up
first — `gh auth login` alone does not create or register an SSH key:

```bash
ssh-keygen -t ed25519 -C "you@example.com"
gh auth refresh -h github.com -s admin:public_key
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(hostname)"
gh config set git_protocol ssh
ssh -T git@github.com    # accept the host key by typing the full word: yes
```

On the first SSH connection you will be asked to verify GitHub's host key fingerprint.
Check it against the current values published at
<https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints>
and answer `yes` — anything else, including a bare Enter, aborts with
`Host key verification failed`.

Then create the directory skeleton:

```bash
mkdir -p sim data/{modules,enemies,rooms} harness shell tests tools/schema docs \
         fixtures reports .github/workflows

echo "4.7.stable" > .godot-version
echo "1" > sim/VERSION
```

Add a `.gitignore`:

```gitignore
.godot/
*.import
android/build/
build/
reports/*.json
!reports/.gitkeep
.DS_Store
```

`reports/` is ignored except for snapshots you deliberately commit as balance evidence.

Drop `CLAUDE.md` at the repo root and the build plan at `docs/plan.md`.

---

## 3. Project configuration

Create `project.godot` by opening the folder once in the Godot editor, then set these
in **Project Settings**:

- **Rendering → Renderer**: Compatibility. The schematic needs nothing more, and it is
  the widest mobile support.
- **Display → Window → Stretch → Mode**: `canvas_items`, aspect `expand`.
- **Display → Window → Size → Viewport Width / Height**: `1080` × `2400`. This is the
  base resolution the stretch mode scales from, matching the Pixel 6a floor device.
- **Display → Window → Handheld → Orientation**: `Sensor`, which the editor writes to
  `project.godot` as `window/handheld/orientation=6` — the integer enum value, not the
  string `"sensor"`. That string is Godot 3 syntax; in Godot 4 it parses but silently
  does nothing, so a text-editor diff review here has to check for the digit `6`, not
  the word. Both portrait and landscape are supported and the player may rotate at any
  time, including mid-run. See *Orientation* below — this is a layout constraint from
  the first scene, not a setting to revisit at M6.
- **Application → Run → Main Scene**: a placeholder empty scene for now.
- **Debug → Settings → Stdout → Print FPS**: off.

Commit `project.godot`. It changes rarely, and when it does it should be visible in a
diff.

### Orientation

Both orientations are supported, and the player can rotate at any time including
mid-run. This is cheap to honour from the start and expensive to retrofit, so it is a
constraint on every layout from the first scene.

What it requires:

- **No fixed pixel layouts.** Anchors, containers and relative sizing only. Never
  position by absolute coordinate, and never assume which dimension is longer.
- **Two layouts per screen, one content model.** Portrait stacks; landscape places
  side by side. Both read from the same state — a rotation is a re-layout, never a
  reload and never a state reset.
- **The schematic viewport scales, it does not crop.** Rotating must not hide part of
  the arena or change what the player can see, because visibility during a run affects
  decisions. Fit the same logical bounds into whichever aspect ratio is available.
- **Rotation mid-run must not touch the sim.** The renderer is a pure function of the
  event log, so a rotation is purely a shell concern. If rotating changes a run's
  outcome or hash, that is a boundary violation and a release blocker.
- **Test both.** Every layout test runs at both reference viewports, plus a
  rotate-mid-run case asserting the log hash is unchanged. Add this to
  `tools/run_tests.gd` at M4.

  | Reference viewport | Size | Aspect | Notes |
  | --- | --- | --- | --- |
  | Portrait | 1080 × 2400 | 20:9 | Base resolution; Pixel 6a, the floor device |
  | Landscape | 2400 × 1080 | 9:20 | Same logical bounds, rotated |

  Tall 20:9 portrait and wide 9:20 landscape are the extremes that break layouts. If
  both hold, tablets and 16:9 handsets sit comfortably between them. Add an iPad-ish
  4:3 case at M5 once the compiler UI exists, since that is where a near-square aspect
  first causes trouble.
- **Safe areas differ per orientation.** Notches and home indicators move; read the
  safe area rather than hardcoding insets.

---

## 4. M0 file skeleton

These are the files M0 creates. Each should be real and tested, not a stub.

```
sim/fx.gd              fixed-point: from_int, to_int, mul, div, lerp, clamp
sim/rng.gd             xorshift128+ — seeded, no global state, serialisable
sim/log.gd             event log: append, serialise, hash
sim/VERSION            "1"
tools/lint.gd          scans sim/ for banned symbols, exits non-zero on a hit
tools/validate_data.gd validates every /data file against tools/schema/
tools/run_tests.gd     discovers and runs everything under tests/
tools/schema/module.json
tools/schema/enemy.json
tools/schema/room.json
tests/test_fx.gd
tests/test_rng.gd
tests/test_determinism.gd
tests/test_lint.gd     asserts the lint CATCHES a planted violation
tests/golden/           committed snapshots (empty until M1)
harness/sim_cli.gd     CLI entry point
fixtures/              canned loadouts and seeds for tests
```

### The lint self-test matters

`tests/test_lint.gd` must plant a file containing `randf()` under a temporary path
inside the lint's scan root and assert the lint rejects it. A lint nobody has seen fail
is a lint that silently stopped working three months ago.

### The fixed-point contract

`sim/fx.gd` uses `int` with 1 unit = 1/1024. Test it against known values including
negatives, division truncation direction, and multiplication overflow at the extremes
of the range you intend to support. Document the truncation direction in a comment,
because a later "tidy-up" that changes rounding will break every golden file.

---

## 5. The CLI

`harness/sim_cli.gd` is how the agent verifies its own work, so build it first and keep
it honest.

```bash
godot --headless --script harness/sim_cli.gd -- run --seed 1234 --loadout fixtures/basic.json
```

It should print, on separate lines:

```
sim_version=1
seed=1234
log_hash=<hex>
outcome=<win|loss>
depth=<int>
choke=<subsystem|none>
```

Machine-readable output first, human detail behind a `--verbose` flag. Every test and
every sweep goes through this entry point, so anything hard to parse here becomes
friction everywhere else.

---

## 6. CI

`.github/workflows/ci.yml`. The essential shape:

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        runner: [ubuntu-latest, ubuntu-24.04-arm]
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - name: Install Godot
        run: |
          # pin the version from .godot-version
      - name: Lint sim boundary
        run: godot --headless --script tools/lint.gd
      - name: Validate data
        run: godot --headless --script tools/validate_data.gd
      - name: Tests
        run: godot --headless --script tools/run_tests.gd
      - name: Determinism probe
        run: |
          A=$(godot --headless --script harness/sim_cli.gd -- run --seed 1234 \
              --loadout fixtures/basic.json | grep log_hash)
          B=$(godot --headless --script harness/sim_cli.gd -- run --seed 1234 \
              --loadout fixtures/basic.json | grep log_hash)
          [ "$A" = "$B" ] || { echo "nondeterministic within platform"; exit 1; }
          echo "$A" > hash-${{ matrix.runner }}.txt
      - uses: actions/upload-artifact@v4
        with:
          name: hash-${{ matrix.runner }}
          path: hash-${{ matrix.runner }}.txt

  cross-platform-hash:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - name: Compare hashes across architectures
        run: |
          # every hash file must be identical
```

The two-architecture matrix is the point. x86 and ARM agreeing on a hash is what proves
the fixed-point discipline is holding, and it is the single test most likely to catch a
future float creeping in.

---

## 7. Branch protection

Required. Set this on GitHub before the first real milestone — Settings → Branches →
Add branch ruleset, targeting `main`:

- Require a pull request before merging (no approvals needed for a solo repo).
- Require status checks to pass: `test (ubuntu-latest)`, `test (ubuntu-24.04-arm)`,
  `cross-platform-hash`.
- Require branches to be up to date before merging.
- Require linear history.
- Block force-pushes.
- Restrict deletions.
- Do **not** grant yourself a bypass. The point is that a failing determinism check
  cannot be merged, including by you at 11pm.

Agent work happens on `milestone/m0`, `milestone/m1` and so on, merged by PR once the
exit criterion passes. Without this, a session that cannot get CI green can merge
anyway, and the exit-criteria discipline the whole plan rests on quietly stops being
real.

---

## 8. Session zero checklist

- [ ] `gh auth status` clean, and a test push to a scratch branch succeeds
- [ ] Repo cloned, directory skeleton created, `.gitignore` committed
- [ ] `.godot-version` and `sim/VERSION` committed
- [ ] `project.godot` configured and committed; orientation is
      `window/handheld/orientation=6` (the int enum for Sensor — not the string
      `"sensor"`), base viewport 1080 × 2400
- [ ] Reference viewports confirmed: 1080 × 2400 portrait, 2400 × 1080 landscape
- [ ] `CLAUDE.md` at root, `docs/plan.md` present
- [ ] `docs/M0.md` written with M0's exit criterion stated as a command
- [ ] Branch protection ruleset active on `main`, no bypass for yourself
- [ ] First session prompt given to Claude Code (below)

## 9. First session prompt

> Read `CLAUDE.md` and `docs/M0.md`. Restate M0's exit criterion. Then implement M0
> only: the directory skeleton, `sim/fx.gd` fixed-point maths, `sim/rng.gd` seeded RNG,
> `sim/log.gd` event log with hashing, the three data schemas, `tools/lint.gd`,
> `tools/validate_data.gd`, `tools/run_tests.gd`, `harness/sim_cli.gd`, and the CI
> workflow with the two-architecture hash comparison. Do not implement any game rules,
> modules, enemies or rooms. Stop when CI is green on both runners and
> `tests/test_lint.gd` proves the lint catches a planted `randf()`.

## 10. What M0 must not contain

No pipeline logic, no encounter resolution, no facility generation, no module or enemy
data beyond whatever minimal fixture the tests need, and no rendering. M0 exists to make
the rest of the project verifiable. If it grows a game rule, the golden-file
infrastructure gets built against a moving target and stops being useful.
