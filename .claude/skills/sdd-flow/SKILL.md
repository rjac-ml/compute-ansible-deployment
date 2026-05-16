---
name: sdd-flow
description: Drive the full Spec-Driven Development pipeline (SpecKit) end-to-end from a single entry point, with a human checkpoint between every phase. Trigger this whenever the user wants the whole `/speckit-specify` → `/speckit-clarify` (if needed) → `/speckit-plan` (research-heavy) → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement` flow orchestrated for them instead of running each slash command manually. Trigger phrases include "/sdd", "/sdd-flow", "/spec-flow", "run the full SDD flow", "drive this spec end-to-end", "do the whole SpecKit pipeline for X", or any spec input given alongside an obvious wish for the full flow ("take this all the way", "go through the whole loop"). The skill pauses after each phase with a multi-option checkpoint — it never barrels through. After `/speckit-implement` it waits for the user's test results before continuing, and on a green run it hands off to the spec-learnings skill (if installed) for retrospective capture.
---

# SDD Flow

Orchestrates SpecKit's full Spec-Driven Development pipeline as a single guided loop. The point isn't to remove the user from the loop — it's to remove the *typing* from the loop. Every phase still ends with the user making a real decision; the skill just makes those decisions explicit and the transitions automatic.

---

## How this skill behaves

When the user invokes the skill (with a spec input — same shape they'd give `/speckit-specify`), the skill:

1. **Pulls forward relevant learnings** before doing anything (if past learnings exist).
2. **Runs each phase in sequence**, calling the underlying SpecKit slash command for that phase.
3. **Stops at every phase boundary** and presents the user a *multi-option* checkpoint — never a yes/no "should I continue?".
4. **Pauses after `/speckit-implement`** for testing. Does not advance until the user reports back.
5. **Triggers the retrospective** at the end via the `spec-learnings` skill, if available.

The checkpoints are the heart of this skill. A good checkpoint is grounded in what the previous phase actually produced — if `/speckit-specify` left auth providers unspecified, "refine the auth provider list" is one of the options. If the spec is clean, that option doesn't appear. **Don't generate boilerplate options.** Read what the phase produced, name the actual things that could go better, and offer those as choices.

---

## The pipeline

| # | Phase | Command | Checkpoint after |
|---|-------|---------|------------------|
| 0 | Pre-flight | (load learnings) | brief context callout, not a stop |
| 1 | Specify | `/speckit-specify` | yes — required |
| 2 | Clarify | `/speckit-clarify` | yes — *and* it's optional |
| 3 | Plan (research-heavy) | `/speckit-plan` | yes — research before, plan after |
| 4 | Tasks | `/speckit-tasks` | yes |
| 5 | Analyze | `/speckit-analyze` | yes — branches on findings |
| 6 | Implement | `/speckit-implement` | yes, before — wait, after — until tests reported |
| 7 | Retrospective | (hand off) | end of flow |

---

## Phase 0 — Pre-flight: pull forward learnings, calibrate the run

Before running `/speckit-specify`, do two things in order:

### 0a — Load relevant learnings

Check for `.specify/memory/learnings.md`. If it exists:

- Scan it for entries relevant to the new spec (match on tags, area, technology, or topic in the user's input).
- Surface the **3–5 most relevant** entries as a brief callout — one or two sentences each, with a pointer to the full entry. Don't dump the whole file.
- If past learnings include action items targeting `/speckit-specify`, *apply them now* before drafting the spec — that's the entire point of recording them.

If `learnings.md` doesn't exist, skip silently.

### 0b — Calibrate the run

Ask the user to size the spec. This single answer calibrates depth throughout the flow (research effort, clarify default, implementation cadence). Suggest a default based on the user's input — short and familiar input → A, longer or unfamiliar → C — but let them override.

```
Quick sizing on this spec (suggested: <A/B/C based on your read>):

  A. Small / well-understood — light research, default to skipping /clarify,
     run /implement in one pass.
  B. Medium / standard — codebase + framework-doc research, /clarify if any
     ambiguity, /implement in one pass with checkpoints if it spans many tasks.
  C. Large / unfamiliar — heavy research including web search, expect /clarify,
     /implement batched with stops between groups of tasks.
  D. Custom — let me set research depth, clarify default, and implementation
     cadence individually.
```

If the user picks D, ask three follow-ups (research depth, clarify default, implementation cadence) and record their answers. Otherwise, carry the A/B/C choice as the run's default profile.

This is the only "advance without an explicit checkpoint" moment — once sizing is set, move straight into Phase 1. Everything from here on stops at phase boundaries.

---

## Phase 1 — `/speckit-specify`

Run `/speckit-specify` with the user's input. Show the resulting spec.

**Checkpoint.** Generate options based on what the spec actually contains. Always include one "proceed" option and one "stop" option; the middle options are spec-dependent. Example shape:

```
The spec is drafted. Where would you like to take it?

  A. Looks right — continue to /speckit-clarify
  B. Looks right and is unambiguous — skip /clarify, go straight to /plan
  C. Refine: <specific section that looks under-specified, named concretely>
  D. Refine: <another concrete area>
  E. Add missing context: <thing the spec doesn't mention but probably should>
  F. Pause — I want to think before continuing
```

The C/D/E slots should be filled with *real observations from the drafted spec*, not placeholders. If the spec is clean and there's nothing concrete to refine, drop those slots — three good options beat six padded ones.

If the user picks a refine option, edit `/speckit-specify`'s output accordingly and re-checkpoint. Don't cascade automatically.

---

## Phase 2 — `/speckit-clarify` (decision phase)

`/speckit-clarify` is optional in SpecKit, and skipping it is sometimes correct. Before running, present a decision checkpoint. The Phase 0 sizing gives a default lean — Small biases toward skip, Medium/Large bias toward run — but the spec content overrides the profile. State the suggested default explicitly so the user sees it.

```
Clarify is optional. Suggested default: <Run / Skip>
(reason: <sizing profile says X> + <what the spec content shows>)

Based on the spec:

  A. Run /speckit-clarify — there are ambiguous areas (<name them>)
  B. Run /speckit-clarify focused on <specific area>
  C. Skip — the spec is unambiguous enough
  D. Skip — but flag <specific concern> for /plan to address directly
```

If past learnings show that skipping `/clarify` has burned the user before in a similar area, override the profile default toward A and say so explicitly ("Past learning #N suggests running /clarify here — ambiguity in auth flows has cost time before").

If `/clarify` runs, show the questions and answers, then checkpoint:

```
  A. Accept clarifications and proceed to /plan
  B. Re-answer <question N> — the answer doesn't feel right
  C. Run another round of /clarify focused on what came up
  D. Go back to /speckit-specify with these clarifications folded in
```

---

## Phase 3 — `/speckit-plan` (research-heavy variant)

This is the phase that benefits most from the skill's interactivity. Default `/speckit-plan` jumps to a plan; this skill **researches first, plans after.**

### Step 3a — Research

Before invoking `/speckit-plan`, do a deliberate research pass. Confirm depth first — the Phase 0 sizing gives a default, but the user can override per-spec since planning often surfaces unexpected complexity.

```
Research depth for the plan (default from sizing: <Light / Medium / Heavy>):

  A. Light — codebase scan only (existing patterns, conventions, dependencies)
  B. Medium — codebase + framework/library docs for the components in scope
  C. Heavy — codebase + docs + web search for current best practices, plus
     re-scan past learnings for technical-pattern entries on this area
  D. Targeted — I'll tell you specifically what to research
```

If the user picks D, ask what to focus on and confine the pass to that.

Then execute the chosen depth:

- **Codebase** (all levels): scan for existing patterns, similar features, conventions, and dependencies that constrain the design.
- **Documentation** (Medium+): read framework/library docs for the components the spec touches.
- **Web** (Heavy only): search current best practices for genuinely unfamiliar territory or fast-moving tooling.
- **Past learnings** (Heavy, and always when relevant): re-scan `learnings.md` for technical-pattern entries.

Synthesize the research into **2–3 candidate approaches**, each with: a one-sentence summary, the main trade-off, and the rough complexity. Don't write the plan yet — write the menu.

```
Researched three approaches:

  A. <approach name> — <one-line summary>
       Trade-off: <main downside>. Complexity: low / medium / high.
  B. <approach name> — <one-line summary>
       Trade-off: ...
  C. <approach name> — <one-line summary>
       Trade-off: ...
  D. None of these — let me describe what I want
  E. Mix A and B (specify how)
```

### Step 3b — Plan

Once the user picks an approach, run `/speckit-plan` *biased toward that approach* (mention it explicitly in the plan invocation). Show the resulting plan. Checkpoint:

```
  A. Plan looks right — proceed to /speckit-tasks
  B. Refine: <specific design decision that looks risky or wrong>
  C. Reconsider approach — go back to 3a
  D. Add a section on <thing the plan doesn't address>
  E. Go back to /speckit-specify — the plan exposed a spec gap
```

The "spec gap" option (E) matters. Plan exposing a spec problem is a healthy outcome, not a failure — going backwards is a real choice, not a punishment.

---

## Phase 4 — `/speckit-tasks`

Run `/speckit-tasks`. Show the resulting task list. Checkpoint:

```
  A. Tasks look right — proceed to /speckit-analyze
  B. Tasks are too granular — combine <which ones>
  C. Tasks are too coarse — break up <which ones>
  D. Missing task: <thing the plan implies but tasks don't cover>
  E. Reorder — <suggested change>
  F. Go back to /speckit-plan — the task breakdown exposed a planning gap
```

Same principle as before: only show options that match what's actually in the task list. If tasks look fine, three options are enough.

---

## Phase 5 — `/speckit-analyze`

Run `/speckit-analyze`. The checkpoint here branches based on what analyze found.

**If analyze finds significant issues:**

```
/speckit-analyze flagged <N> issues. The most consequential:
  - <issue 1>
  - <issue 2>

  A. Address all flagged issues before /implement
  B. Address only <specific issues>, defer the rest
  C. Discuss issue <N> — I'm not sure analyze is right
  D. Proceed to /implement and accept the risks (record which in learnings)
  E. Loop back to /plan — the issues are too structural to patch in tasks
```

**If analyze is clean:**

```
/speckit-analyze is clean. Ready to implement.

  A. Proceed to /speckit-implement
  B. One more pass — <specific concern I want re-checked>
  C. Pause here — I want to review before implementing
```

Option D in the "issues found" branch — proceeding *with* known risks — should record those risks somewhere the retrospective will see them later. A short note in the spec or a comment in the plan is enough; the goal is "future-you knows these risks were chosen, not missed."

---

## Phase 6 — `/speckit-implement`

### Before running

Final pre-flight checkpoint. The Phase 0 sizing sets the default cadence — Small/Medium → one pass, Large → batched — but the user can override.

```
Ready to run /speckit-implement. (Default cadence from sizing: <one pass / batched>)

  A. Run it (one pass — execute the full task list)
  B. Run only tasks <N>–<M>, stop and check before continuing
  C. Run in batches (suggested split: <natural groupings from the task list>)
  D. Dry-run first — show what will be touched without changing anything
  E. Pause — I want to commit current state first
```

### After running

Show what was implemented (files changed, tests added, anything notable). Then **stop and wait for testing.** Do not advance.

State explicitly: *"Implementation done. Run your tests / manual checks and report back — I'll wait."*

### When the user reports back

This is the most important branch in the whole flow. Read what they say carefully.

**If tests pass / behavior is correct:**

```
  A. Ship it — run the retrospective (hand off to spec-learnings)
  B. Ship it later — capture learnings now while it's fresh
  C. Hold off — there's polish I want to do first
```

**If tests fail / behavior is wrong:**

```
  A. Fix forward — let me debug and re-run /speckit-implement on specific tasks
  B. Roll back to <earlier phase> — the failure suggests <plan / tasks / spec> was wrong
  C. Capture learnings about what went wrong before fixing — this one's worth recording
  D. Pause — let me look at this myself
```

Don't try to silver-line failures. If something broke, surface it cleanly and let the user pick the response.

---

## Phase 7 — Retrospective handoff

When the user is ready to close out, hand off to the `spec-learnings` skill if it's installed. That skill knows how to run the actual retro — this skill's job is just to make sure the handoff happens at the right moment (which is: while the work is still fresh in everyone's head, not three weeks later).

If `spec-learnings` isn't installed, do a minimal version inline: ask three questions — what worked, what didn't, what's the one thing worth remembering — and append the answers to `.specify/memory/learnings.md` (creating the file if needed). Then suggest the user install the dedicated skill for next time.

---

## Cross-cutting: the checkpoint pattern

Every checkpoint follows the same shape:

1. **State what just happened** in one line ("Spec drafted." / "Plan complete." / "Implementation done.").
2. **Offer 3–6 options**, lettered. Each option must:
   - Be specific and actionable, not generic.
   - Be grounded in the actual output of the previous phase.
   - Map to a concrete next behavior (not "think about it").
3. **Always include** at least one "proceed" path and one "go backwards" path. Going backwards is a normal choice in SDD, not a failure.
4. **Don't ask "ready to continue?"** — that's a useless checkpoint. The whole point is to make the user *choose between paths*, not just gate on attention.

When the user replies to a checkpoint, do exactly what they picked. If their reply is between options or extends one ("B but also C"), confirm the interpretation in one sentence before acting.

---

## Cross-cutting: going backwards

SDD is iterative — a downstream phase often exposes upstream gaps. When a checkpoint includes a "go back to phase N" option and the user picks it:

- **Carry context forward.** Don't restart that phase from scratch; pass in what was learned downstream so the second pass is informed by the first.
- **Don't auto-re-run the intervening phases.** After redoing the upstream phase, checkpoint again before continuing — the user may want to revisit each downstream phase deliberately rather than have them silently re-cascade.
- **Note the loop in the eventual retro.** Backward jumps are signal — they tell the retrospective which phase was under-specified the first time. Mention them when handing off to `spec-learnings`.

---

## Cross-cutting: when not to use this skill

This skill is overkill for tiny specs (a one-task tweak, a typo fix, a config change). If the user's input is clearly small, suggest running `/speckit-specify` directly without the orchestration. The checkpoint overhead is only worth it for specs where one of the phases might genuinely change direction.
