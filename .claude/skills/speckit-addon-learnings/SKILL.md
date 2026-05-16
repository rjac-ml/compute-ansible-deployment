---
name: "speckit-addon-learnings"
description: Capture and reuse lessons learned across Spec-Driven Development cycles. Use this skill at the end of a spec (after Specify → Plan → Tasks → Implementation) to run a focused retrospective that records what worked, what didn't, technical patterns discovered, and agent-behavior notes — and at the start of a new spec to surface relevant past learnings. Trigger this whenever the user mentions wrapping up a spec, closing one out, "lessons learned", "retro", "retrospective", "what did we learn", or whenever a /specify, /plan, /tasks, or /implement cycle visibly concludes (tests pass, PR opened, "we're done", "shipping this"). Also trigger at the start of a new spec to load existing learnings before drafting. Use even when the user doesn't explicitly say "skill" — the value is in making the loop habitual.
---

# Spec Learnings

A retrospective + memory skill for Spec-Driven Development (SDD). It does two jobs:

1. **At spec close** — runs a focused retro and appends a structured entry to a learnings file.
2. **At spec start** — loads the learnings file and surfaces the few entries most relevant to what the user is about to work on.

The point is to make each spec slightly cheaper than the last, by feeding hard-won knowledge forward instead of letting it evaporate.

---

## Where learnings live

Detect the storage path in this order. Don't ask the user unless none of these match:

1. **`.specify/memory/learnings.md`** — if a `.specify/` directory exists (this is the SpecKit convention; SpecKit's templates already load files from `memory/` automatically, so writing here means future `/specify` runs get the context for free).
2. **`specs/LEARNINGS.md`** — if a `specs/` directory exists but no `.specify/`.
3. **`LEARNINGS.md`** at the repo root — fallback.

If the file doesn't exist yet, create it with a short header explaining the format (see the template at the bottom of this file). Always confirm the path with the user the first time you write to it in a session.

**Relationship to `constitution.md` (SpecKit users):** if `.specify/memory/constitution.md` exists, treat it as immutable principles (the rules of the project) and `learnings.md` as evolving experience (what we've discovered while applying those rules). Don't duplicate constitution items as learnings. If a learning becomes a stable principle over time, suggest promoting it to the constitution rather than repeating it across retros.

---

## When to capture (closing out a spec)

Trigger a retro in any of these cases:

- **Explicit:** the user says "close out the spec", "capture learnings", "spec retro", "wrap up", "what did we learn", or similar.
- **Proactive:** the implementation phase visibly concludes — PR opened, tests passing, "we're done", "shipping it", "let's move on", or the user starts a clearly different topic right after finishing one. In proactive cases, **ask first** (one short line: "Want to capture learnings from this spec before we move on?"). Don't write unilaterally.

If the user declines the proactive offer, drop it — don't re-prompt in the same conversation.

### How to run the retro

A bad retro produces generic advice ("communicate better!", "plan more carefully!"). A good retro produces *specific, reusable* observations tied to concrete moments in the spec. Your job is to extract the latter.

Walk through the spec phase by phase and ask targeted questions. Don't dump all questions at once — work through them conversationally, two or three at a time, following threads as they appear. The user knows the spec; you're helping them notice patterns they might otherwise lose.

**Specify phase:**
- Where did the spec need clarification mid-implementation? (signals ambiguity that should have been resolved earlier)
- What requirement got discovered late? What would have surfaced it sooner?
- Did the spec match what actually shipped? If not, where did it drift?

**Clarify phase (if `/speckit-clarify` was used):**
- Did the questions `clarify` surfaced match the ambiguities that actually bit you later? Misses are gold — note them.
- Were there clarifications you accepted that turned out wrong, or that you'd answer differently now?
- If `clarify` *wasn't* used: is there a moment downstream where it clearly would have helped? Which question would have prevented the rework?

**Plan phase:**
- Did the plan survive contact with the code? What had to change?
- Were there design decisions you'd reconsider? Why?
- Anything in the plan that turned out to be over- or under-specified?

**Tasks phase:**
- Were tasks the right size? Too granular, too coarse?
- Any tasks that should have been broken up or combined?
- What dependencies between tasks weren't obvious upfront?

**Implementation phase:**
- What did you have to redo, and why?
- Where did Claude get stuck or go off-track? What kind of nudge unstuck it?
- What patterns did you discover (in the codebase, in the framework, in the prompts) that you'd want to reuse?
- Any anti-patterns to avoid next time?

**Cross-cutting:**
- What surprised you? (Surprises are usually unknown-unknowns worth recording.)
- What would you do differently if you started this spec over?
- What's one thing from this spec that, if you don't write it down, you'll forget by next month?

You don't need to ask every question — pick the ones the spec actually warrants. A small spec might need three questions; a fraught one might need ten.

### Writing the entry

After the conversation, **synthesize, don't transcribe.** A learning entry should be terse, scannable, and grounded in specifics. Bad: "Communication was hard." Good: "When the spec said 'support OAuth', it didn't specify which providers. Cost ~2 hours of back-and-forth in /plan. Next time: list providers explicitly in /specify, even if just 'Google + GitHub for v1'."

Show the user the draft before appending. Let them edit, cut weak items, or add things you missed. Then append to the learnings file.

Use this entry format (see the bottom of this file for the file-level template that wraps these):

```markdown
## YYYY-MM-DD — Spec: <name or number>

**Outcome:** shipped | partial | abandoned
**Tags:** #area1 #area2 #pattern-name

### What worked
- Specific thing that went well, and *why* it went well

### What didn't
- Specific friction point, with enough context that future-you remembers it

### Technical patterns discovered
- Pattern: <name>. Use when <condition>. Avoid when <condition>.
- Or: Anti-pattern: <name>. Symptom: <what you'll see>. Fix: <what to do instead>.

### Agent / prompt notes
- Where Claude got it right or wrong, and what prompt shape worked
- E.g., "Claude over-engineered the migration script until I added 'prefer the simplest reversible approach' to the plan"

### Action items for next specs
- [ ] Concrete change to make in the next /specify, /plan, /tasks, or /implement
- [ ] Each item should be specific enough that you'd know whether you did it
```

Keep entries short. If an entry is longer than ~30 lines, it's probably trying to capture a whole essay and should be trimmed to the punchlines. The goal is something a tired future-you can skim in 30 seconds.

---

## When to load (starting a new spec)

Trigger a load in these cases:

- The user runs `specify` or starts describing a new spec.
- The user says "new spec", "starting on X", "let's plan Y", or similar.
- The user asks "have we done something like this before?" or "any lessons from past work on Z?"

### How to load

1. Read the learnings file (using the detection order above).
2. **Don't dump it back at the user.** Scan it and pick the **3–5 entries most relevant** to the new spec's topic, area, or technical surface. Match on tags, spec names, file paths mentioned, or technologies referenced.
3. Surface them as a brief callout — one or two sentences each, with a pointer to the full entry. Something like:

   > **Relevant past learnings (3):**
   > - *Spec 014 (auth migration):* OAuth provider list needs to be explicit in /specify — see action item.
   > - *Spec 019 (data import):* Anti-pattern: parsing CSV in the same task as DB write. Split them.
   > - *Spec 022 (API redesign):* Claude tends to over-engineer migration scripts; nudge toward "simplest reversible."

4. Then proceed with the spec. The point is a quiet handoff, not a lecture.

If no entries are relevant, say so briefly and move on. Don't pad.

If the learnings file doesn't exist yet, just proceed normally — this is the first spec to use the skill, and there's nothing to load.

---

## File template (first time only)

When you create the learnings file for the first time, start it with this header so future readers (human and agent) understand what they're looking at:

```markdown
# Spec Learnings

A running log of lessons learned from Spec-Driven Development cycles in this repo.
Each entry is a focused retrospective from one spec. New entries are appended at the bottom.

When starting a new spec, scan this file for relevant past learnings (match on tags, area, or topic) and surface the most relevant 3–5 entries before drafting.

Entry format:

## YYYY-MM-DD — Spec: <name>
**Outcome:** shipped | partial | abandoned
**Tags:** #tag1 #tag2

### What worked
### What didn't
### Technical patterns discovered
### Agent / prompt notes
### Action items for next specs

---

<!-- Entries below, newest at the bottom -->
```

---

## A few cross-cutting principles

**Specificity beats volume.** Three sharp learnings are worth more than fifteen vague ones. If a learning could apply to any project, it's too generic — push for the version that's grounded in *this* spec.

**Action items are the real product.** The "what worked / didn't" sections are useful, but action items are what change behavior on the next spec. Every retro should produce at least one concrete action item, even if small.

**Tag consistently.** Tags are how you'll find relevant entries later. Reuse existing tags from the file when they fit; only invent new ones when nothing matches. Common tags worth establishing early: `#ambiguity`, `#scope-creep`, `#testing`, `#migration`, `#refactor`, `#agent-behavior`, plus your project's domain areas (`#auth`, `#billing`, etc.).

**Don't editorialize past entries.** Treat existing learnings as immutable history. If a past learning turned out to be wrong, write a new entry that supersedes it — don't rewrite the old one.

**The file should stay scannable.** If it grows past ~50 entries or the file gets unwieldy, suggest archiving older entries to `.specify/memory/learnings-archive-YYYY.md` and keeping the active file lean. The action items from archived entries can be promoted into a permanent "standing principles" section at the top of the active file if they've proven repeatedly true.
