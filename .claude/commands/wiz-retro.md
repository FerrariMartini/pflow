---
description: Run a phase retrospective, deciding accepted debt vs guideline update vs ADR for each recurring finding
argument-hint: "<slug> <phase-number>"
---

# Phase Retrospective

You are closing out a phase using the Wiz Planner workflow, deciding what happens to every finding accumulated across its milestone and phase reviews.

## Arguments

- `<slug>`: PRD slug
- `<phase-number>`: Phase number to retrospect (1, 2, 3, etc.)

## Retro Agent

This command delegates the analysis to the **wiz-retro-analyst** agent (`wiz-retro-analyst`), which groups findings by deviation type across all reviews of the phase and decides, per group, whether it stays as accepted debt, becomes a guideline update, or becomes an ADR.

## Command Overview

This command performs a phase retrospective to:
- Confirm the phase is closed (all milestones `✅ COMPLETE`, phase review present)
- Collect every review note produced during the phase (`.wiz/<slug>/reviews/milestone-*-review.md` and `phase-<n>-review.md`)
- Delegate grouping and decision-making to `wiz-retro-analyst`
- Save the retro report to `.wiz/<slug>/retros/phase-<n>-retro.md`
- Surface any guideline updates or ADRs recommended, so they can be applied in a follow-up

Unlike `/wiz-review-phase` (which audits one phase in isolation), a retro's value comes from comparing findings **across** the reviews of that phase to catch repeated deviations that a single review would call a one-off.

## Embedded Utility Functions

### Logging Functions

```bash
# Check if terminal supports colors
_wiz_supports_color() {
    [[ -t 2 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]
}

# Color codes - only set if not already set
if [[ -z "${WIZ_COLOR_RESET+x}" ]]; then
    if _wiz_supports_color; then
        WIZ_COLOR_RESET="\033[0m"
        WIZ_COLOR_RED="\033[31m"
        WIZ_COLOR_YELLOW="\033[33m"
        WIZ_COLOR_BLUE="\033[34m"
        WIZ_COLOR_GRAY="\033[90m"
    else
        WIZ_COLOR_RESET=""
        WIZ_COLOR_RED=""
        WIZ_COLOR_YELLOW=""
        WIZ_COLOR_BLUE=""
        WIZ_COLOR_GRAY=""
    fi
    readonly WIZ_COLOR_RESET WIZ_COLOR_RED WIZ_COLOR_YELLOW WIZ_COLOR_BLUE WIZ_COLOR_GRAY 2>/dev/null || true
fi

_wiz_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

wiz_log_info() {
    local message="$*"
    echo -e "${WIZ_COLOR_BLUE}[$(_wiz_timestamp)] INFO:${WIZ_COLOR_RESET} $message" >&2
}

wiz_log_warn() {
    local message="$*"
    echo -e "${WIZ_COLOR_YELLOW}[$(_wiz_timestamp)] WARN:${WIZ_COLOR_RESET} $message" >&2
}

wiz_log_error() {
    local message="$*"
    echo -e "${WIZ_COLOR_RED}[$(_wiz_timestamp)] ERROR:${WIZ_COLOR_RESET} $message" >&2
}
```

### Validation Functions

```bash
# wiz_validate_slug - Validate slug format
wiz_validate_slug() {
    local slug="$1"

    if [[ -z "$slug" ]]; then
        wiz_log_error "Slug cannot be empty"
        return 1
    fi

    if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        wiz_log_error "Invalid slug: '$slug'"
        wiz_log_error "Slug must be lowercase, alphanumeric, with hyphens (not at start/end)"
        return 1
    fi

    return 0
}
```

## Execution Steps

### Step 1: Validate Arguments

```bash
#!/usr/bin/env bash
set -euo pipefail

SLUG="${1:-}"
PHASE_NUMBER="${2:-}"

if [[ -z "$SLUG" || -z "$PHASE_NUMBER" ]]; then
    echo "Usage: /wiz-retro <slug> <phase-number>"
    echo ""
    echo "Example: /wiz-retro backoffice-api 2"
    exit 1
fi

if ! wiz_validate_slug "$SLUG"; then
    echo "Error: Invalid slug format: $SLUG"
    exit 1
fi

if ! [[ "$PHASE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Phase number must be a positive integer"
    exit 1
fi

PRD_FILE=".wiz/$SLUG/prd.md"
if [[ ! -f "$PRD_FILE" ]]; then
    echo "Error: PRD not found: $PRD_FILE"
    echo "Run /wiz-prd $SLUG first"
    exit 1
fi

PHASE_FILE=".wiz/$SLUG/phases/phase${PHASE_NUMBER}.md"
if [[ ! -f "$PHASE_FILE" ]]; then
    echo "Error: Phase file not found: $PHASE_FILE"
    echo "Run /wiz-phases $SLUG first"
    exit 1
fi

wiz_log_info "Preparing retro for phase $PHASE_NUMBER of PRD: $SLUG"
```

### Step 2: Confirm the Phase Is Closed

```bash
COMPLETE_COUNT=$(grep -c '✅ COMPLETE' "$PHASE_FILE" || echo "0")
TODO_COUNT=$(grep -c '🚧 TODO' "$PHASE_FILE" || echo "0")
IN_PROGRESS_COUNT=$(grep -c '🏗️ IN PROGRESS' "$PHASE_FILE" || echo "0")
TOTAL_MILESTONES=$((TODO_COUNT + IN_PROGRESS_COUNT + COMPLETE_COUNT))

if [[ $TODO_COUNT -gt 0 || $IN_PROGRESS_COUNT -gt 0 ]]; then
    echo ""
    echo "⚠️  Phase Not Ready for Retro"
    echo ""
    echo "Phase: $PHASE_NUMBER"
    echo "Status:"
    echo "  ✅ Complete:     $COMPLETE_COUNT"
    echo "  🏗️  In Progress:  $IN_PROGRESS_COUNT"
    echo "  🚧 TODO:         $TODO_COUNT"
    echo ""
    echo "All milestones must be complete before a phase retro."
    echo "Run /wiz-next to continue implementation, or /wiz-review-phase $SLUG $PHASE_NUMBER first."
    echo ""
    exit 0
fi

wiz_log_info "Phase $PHASE_NUMBER has $TOTAL_MILESTONES milestones, all complete"
```

### Step 3: Collect Review Notes for the Phase

```bash
REVIEWS_DIR=".wiz/$SLUG/reviews"

if [[ ! -d "$REVIEWS_DIR" ]]; then
    wiz_log_warn "No reviews directory found at $REVIEWS_DIR"
    echo ""
    echo "No review notes found for this phase. Consider running:"
    echo "  /wiz-review-milestone $SLUG <milestone-id>  (per milestone)"
    echo "  /wiz-review-phase $SLUG $PHASE_NUMBER        (whole phase)"
    echo ""
    echo "A retro without review notes has nothing to aggregate. Aborting."
    exit 0
fi

# Milestone IDs that belong to this phase follow the P0<phase>M0<n> pattern
MILESTONE_PATTERN="P0${PHASE_NUMBER}M"
mapfile -t REVIEW_FILES < <(find "$REVIEWS_DIR" -maxdepth 1 -type f -name "milestone-${MILESTONE_PATTERN}*-review.md" | sort)

PHASE_REVIEW_FILE="$REVIEWS_DIR/phase-${PHASE_NUMBER}-review.md"
if [[ -f "$PHASE_REVIEW_FILE" ]]; then
    REVIEW_FILES+=("$PHASE_REVIEW_FILE")
fi

if [[ ${#REVIEW_FILES[@]} -eq 0 ]]; then
    wiz_log_warn "No review notes found for phase $PHASE_NUMBER under $REVIEWS_DIR"
    echo ""
    echo "Nothing to retrospect: run /wiz-review-milestone or /wiz-review-phase first."
    exit 0
fi

wiz_log_info "Found ${#REVIEW_FILES[@]} review note(s) for phase $PHASE_NUMBER"
```

### Step 4: Delegate to wiz-retro-analyst Agent

**⚠️ CRITICAL: Agent File Operation Limitation**

Agents invoked via agent references **cannot reliably write files**. This is a known limitation.

**Solution:**
- The `wiz-retro-analyst` agent **returns the retro report content** as a markdown code block in its response
- The main agent (you, running /wiz-retro) **performs all Write operations**
- Agent focuses on: grouping findings, deciding per-group outcomes, drafting guideline/ADR text
- Main agent handles: all file I/O operations

**Workflow:**
1. Read the full content of every file in `REVIEW_FILES`
2. Reference `wiz-retro-analyst` with the prompt template below
3. Agent returns the retro report as markdown in a code block
4. Main agent writes the retro report file using the Write tool
5. Main agent displays a summary to the user, calling out any guideline updates or ADRs that still need to be applied by hand

Reference the `wiz-retro-analyst` agent with the following prompt:

```
Run a phase retrospective: Phase {PHASE_NUMBER} of PRD {SLUG}

## Context

### Phase Information

File: {PHASE_FILE}
Title: {PHASE_TITLE}

### Review Notes to Analyze

{For each file in REVIEW_FILES, include its path and full content}

## Your Task

1. Extract every finding (issue, warning, accepted debt) from the review notes above — skip criteria that simply passed.
2. Group findings by deviation type, not by which milestone they came from.
3. For each group, decide exactly one outcome: Accepted Debt, Guideline Update, or ADR — following the criteria in your agent instructions.
4. Return the full retro report using the structured output format from your agent instructions.
```

### Step 5: Generate and Save Retro Report

```bash
RETROS_DIR=".wiz/$SLUG/retros"
mkdir -p "$RETROS_DIR"

RETRO_FILE="$RETROS_DIR/phase-${PHASE_NUMBER}-retro.md"

# Extract the retro report from the agent response (markdown code block)
# and write it to RETRO_FILE using the Write tool.

echo "Retro complete!"
echo ""
echo "Report saved to: $RETRO_FILE"
echo ""
echo "Summary of outcomes:"
echo "  [Summary will be provided by wiz-retro-analyst agent]"
echo ""
echo "Next steps:"
echo "  - Apply any recommended guideline updates under docs/technical/guidelines/"
echo "  - Create any recommended ADRs under docs/decisions/"
echo "  - Accepted debt items stay as-is until their reopening trigger fires"
echo ""
```

## Example Output

```
📋 Phase Retro: Transactions and Reconciliation

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PRD: backoffice-api
Phase: 2
Milestones: 5 (all complete)
Review notes analyzed: 4

[Agent groups findings and decides...]

Retro complete!

Report saved to: .wiz/backoffice-api/retros/phase-2-retro.md

Summary of outcomes:
  📌 1 guideline update recommended (docs/technical/guidelines/dependency-injection.md)
  📄 0 ADRs recommended
  ✅ 1 item kept as accepted debt (reopening trigger documented)

Next steps:
  - Apply the guideline update above
  - Run /wiz-phases backoffice-api to start Phase 3
```

## Error Handling

- **Missing slug or phase number**: Show usage
- **Invalid slug format**: Error message
- **Invalid phase number**: Error message with format requirements
- **PRD not found**: Suggest running /wiz-prd
- **Phase file not found**: Suggest running /wiz-phases
- **Phase not complete**: Show status, suggest /wiz-next or /wiz-review-phase
- **No review notes found**: Abort with guidance to run /wiz-review-milestone or /wiz-review-phase first — a retro needs review notes to aggregate

## Notes

- Retro should only be performed when the phase's milestones are all complete
- Retro delegates analysis to the `wiz-retro-analyst` agent
- Report saved to `.wiz/<slug>/retros/phase-<n>-retro.md`
- A retro looks **across** milestone/phase reviews of the same phase, unlike `/wiz-review-phase` which audits a single phase in isolation
- Every finding group gets exactly one decision: accepted debt (with a reopening trigger), guideline update (with target file and changelog entry), or ADR (with a draft)
- Agent returns the report as a markdown code block; the main agent writes the file
- This command and agent extend the original wiz-cursor kit — see `.claude/NOTICE.md`
