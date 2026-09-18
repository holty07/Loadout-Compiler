# CLAUDE.md

Standing instructions for Claude Code working on **Loadout Compiler**. These rules
survive every session. Read this file and `docs/plan.md` before writing any code.

---

## What this project is

A mobile roguelite. The player assembles a weapon system from modules, picks a route
through a procedurally generated facility, and commits. The run then executes as a
**deterministic simulation** rendered as a top-down schematic, which the player watches
and can scrub through. Death is diagnostic: the run report names the module that choked
and the tick it failed on.

Engine: **Godot 4.7**, GDScript. Targets: iOS and Android.

## The one architectural rule everything else follows from

**The game is a deterministic simulation with a renderer bolted on.**

```
(seed, loadout, route, interventions) -> sim -> event log -> shell (renders)
                                                          -> harness (measures)
```

The event log is the only interface between the sim and anything else. The shell and
the harness are both consumers of it. Neither may reach into sim state.

If you are ever unsure whether something belongs in `sim/` or `shell/`, ask: does it
change the outcome of a run? If yes, it is `sim/`. If it only changes what the player
sees, it is `shell/`.

---

## Hard rules — never break these

These are not style preferences. Each one, if broken, silently destroys a feature the
whole design depends on.

1. **Never regenerate golden files to make a test pass.** A failing golden file means a
   rule changed. Report it and stop. If the change was intended, it goes in its own
   commit prefixed `RULES:` or `BALANCE:` with the new snapshots and nothing else.
2. **Never widen a test's tolerance, skip a test, or mark one flaky** to get a green
   build. Report the failure instead.
3. **Never put a balance number in GDScript.** Every stat, rate, threshold, cost and
   curve constant lives in `/data` as TOML. Layout and styling constants under `shell/`
   are the only numeric literals permitted anywhere.
4. **Never import a Godot API under `sim/`.** No `Node`, `Engine`, `Time`, `OS`,
   `Input`, `randf`, `randi`, `randomize`, no `res://shell` path, no file I/O at
   runtime. The lint in `tools/lint.gd` enforces this; do not add exemptions to it.
5. **Never use floats in the sim.** All sim arithmetic is integer fixed-point via
   `sim/fx.gd`, where 1 unit = 1/1024. Float determinism across ARM and x86 is not
   guaranteed and the entire design leans on a seed reproducing identically on a phone,
   on the desktop, and in CI.
6. **Never create a second RNG.** One seeded instance from `sim/rng.gd`, threaded
   explicitly through every call that needs it. No module holds its own.
7. **Never adjust an exit criterion to make a milestone pass.** If a criterion cannot
   be met, stop and report why.
8. **Bump `sim/VERSION`** in any commit that changes output for an existing seed, and
   say so in the commit message.

## Determinism is the product

It is what buys shareable build codes, daily seeds, spectatable runs, and an automated
balance rig that replaces thousands of hours of playtesting. Treat any nondeterminism
as a release blocker, not a bug.

Sources of nondeterminism to watch for: dictionary iteration order, `Array.sort()`
without a stable comparator, float arithmetic, wall-clock reads, node-order dependence,
and any RNG draw added or removed from the middle of the tick sequence.

---

## Layer contracts

| Layer | May depend on | Owns | Never does |
| --- | --- | --- | --- |
| `sim/` | `fx.gd`, parsed `/data` structs | All game rules | Touch the scene tree, RNG creation, clock or I/O |
| `shell/` | `sim/` types (read-only), Godot | Rendering, input, UI, audio | Contain any rule or balance number |
| `harness/` | `sim/` | Sweeps, reports | Modify `/data` |
| `data/` | nothing | Every balance number | Contain logic |

The renderer must be a **pure function of the event log**. There is a test for this:
render tick N by playing the log forward from zero, then again by jumping directly to
N, and assert the resulting view state is identical. If the shell can compute anything
itself, scrubbing backwards stops being correct and the harness stops being a valid
model of the game.

**Both orientations are supported.** The player may rotate at any time, including
mid-run. Anchors and containers only — no absolute positioning, no assumption about
which dimension is longer. A rotation is a re-layout, never a reload and never a state
reset. Because the renderer is a pure function of the event log, rotating cannot affect
a run: if it changes an outcome or a log hash, that is a boundary violation and a
release blocker. Every layout test runs at both reference viewports: **1080 × 2400
portrait** (the base resolution, matching the Pixel 6a floor device) and **2400 × 1080
landscape**.

## Repo layout

```
/sim          pure GDScript — no scene tree, no engine calls
  fx.gd         fixed-point maths
  rng.gd        xorshift128+, explicitly seeded and passed
  loadout.gd    module assembly and validation
  pipeline.gd   feed -> chamber -> cooling -> targeting resolution
  encounter.gd  per-room combat resolution
  facility.gd   route and room generation
  run.gd        top-level run loop; returns an event log
  log.gd        event log construction and hashing
  VERSION       integer, bumped on any behaviour change
/data         TOML — every balance number
  modules/      one file per module
  enemies/
  rooms/
  tuning.toml   global curves and constants
/harness      CLI, sweep runner, report generator
/shell        scenes, schematic renderer, UI, audio
/tests        determinism, golden files, schema validation, perf
/tools        lint rules, data validator, build scripts
/docs         plan.md, plus one spec file per milestone
```

---

## Session workflow

**One milestone per session.** Milestones and their exit criteria are in
`docs/plan.md` and expanded in `docs/M<n>.md`.

At the start of a session:

1. Read `CLAUDE.md` and `docs/M<n>.md`.
2. Restate the milestone's exit criterion in your own words before writing code.
3. Confirm the previous milestone's criterion still passes on a clean checkout.

At the end of a session:

- The exit criterion passes in CI on a clean checkout, or it does not. There is no
  "mostly working". Say which, plainly.
- Do not start the next milestone in the same session.

## Definition of done

A milestone is done when its exit criterion passes in CI on a clean checkout. Not when
it works locally, and not when you believe it works. The criteria are written to be
executable for exactly this reason.

---

## Commands

```bash
# Run a single simulated run and print its event log + hash
godot --headless --script harness/sim_cli.gd -- run --seed 1234 --loadout fixtures/basic.json

# Full test suite (what CI runs)
godot --headless --script tools/run_tests.gd

# Lint the sim boundary
godot --headless --script tools/lint.gd

# Validate every data file against its schema
godot --headless --script tools/validate_data.gd

# Balance sweep (interactive: 2000 seeds; nightly: 20000)
godot --headless --script harness/sweep.gd -- --matrix harness/loadouts.toml --seeds 2000 --out reports/
```

## Commit conventions

| Prefix | For | Extra requirement |
| --- | --- | --- |
| `RULES:` | A change to sim behaviour | Bump `sim/VERSION`; update golden files in the same commit and nothing else |
| `BALANCE:` | A data-only tuning change | Include the sweep report diff |
| `SHELL:` | Rendering, UI, audio | Must not touch `sim/` or `data/` |
| `HARNESS:` | Sweep and reporting tooling | — |
| `CHORE:` | Build, CI, tooling, docs | — |

Keep commits small enough that a failing golden file points at one cause.

## GDScript conventions

- Static typing everywhere: typed parameters, return types, and `var x: int = 0`.
- `class_name` only where a type is genuinely referenced across files.
- No `@onready` or signals under `sim/` — it is plain classes, not nodes.
- Prefer explicit arguments over module-level state. The sim should be callable twice in
  the same process with no shared state between calls; there is a test for this.
- Every function in `sim/` should be reasoned about as pure unless it is documented as
  mutating a passed-in state struct.

---

## Where you will be weakest

Milestone M6 — feel, readability, pacing, onboarding. These are judgement calls with no
test to hang them on. Do not claim them as done. Build the mechanism, then hand it over
for human review and say explicitly what you could not verify.

Everything before M6 is genuinely verifiable. Lean on that: prove it with a test rather
than asserting it in a summary.

## When you are stuck or the spec is ambiguous

Write the question down in `docs/open-questions.md` with the milestone it blocks, then
either pick the option that preserves determinism and data-driven balance, or stop if
neither option does. Do not invent a rule that adds a new source of randomness or a new
hardcoded number.
