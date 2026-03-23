#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
ERRORS=""

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+="  FAIL: $1"$'\n'; echo "  FAIL: $1"; }

echo "=== install.sh tests ==="

# Test: fails when skills/do/ source is missing
echo "[1] Rejects missing source directory"
TMPDIR_TEST=$(mktemp -d)
cp "$SCRIPT_DIR/install.sh" "$TMPDIR_TEST/"
if output=$(bash "$TMPDIR_TEST/install.sh" 2>&1); then
  fail "should have exited non-zero for missing skills/do/"
else
  if echo "$output" | grep -q "skills/do/ not found"; then
    pass "correct error for missing source"
  else
    fail "wrong error message: $output"
  fi
fi
rm -rf "$TMPDIR_TEST"

# Test: fails when ~/.claude doesn't exist
echo "[2] Rejects missing ~/.claude directory"
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/skills/do"
cp "$SCRIPT_DIR/install.sh" "$TMPDIR_TEST/"
if output=$(HOME="$TMPDIR_TEST/fakehome" bash "$TMPDIR_TEST/install.sh" 2>&1); then
  fail "should have exited non-zero for missing ~/.claude"
else
  if echo "$output" | grep -q "Is Claude Code installed"; then
    pass "correct error for missing ~/.claude"
  else
    fail "wrong error message: $output"
  fi
fi
rm -rf "$TMPDIR_TEST"

# Test: succeeds and creates symlink
echo "[3] Creates symlink successfully"
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/skills/do"
mkdir -p "$TMPDIR_TEST/fakehome/.claude"
cp "$SCRIPT_DIR/install.sh" "$TMPDIR_TEST/"
if output=$(HOME="$TMPDIR_TEST/fakehome" bash "$TMPDIR_TEST/install.sh" 2>&1); then
  if [ -L "$TMPDIR_TEST/fakehome/.claude/skills/do" ]; then
    pass "symlink created"
  else
    fail "symlink not found after install"
  fi
else
  fail "install.sh exited non-zero: $output"
fi
rm -rf "$TMPDIR_TEST"

# Test: replaces existing symlink
echo "[4] Replaces existing symlink"
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/skills/do"
mkdir -p "$TMPDIR_TEST/fakehome/.claude/skills"
ln -s /tmp/nonexistent "$TMPDIR_TEST/fakehome/.claude/skills/do"
cp "$SCRIPT_DIR/install.sh" "$TMPDIR_TEST/"
if output=$(HOME="$TMPDIR_TEST/fakehome" bash "$TMPDIR_TEST/install.sh" 2>&1); then
  target=$(readlink "$TMPDIR_TEST/fakehome/.claude/skills/do")
  if echo "$target" | grep -q "$TMPDIR_TEST/skills/do"; then
    pass "symlink replaced correctly"
  else
    fail "symlink points to wrong target: $target"
  fi
else
  fail "install.sh exited non-zero: $output"
fi
rm -rf "$TMPDIR_TEST"

# Test: backs up existing directory
echo "[5] Backs up existing directory at target"
TMPDIR_TEST=$(mktemp -d)
mkdir -p "$TMPDIR_TEST/skills/do"
mkdir -p "$TMPDIR_TEST/fakehome/.claude/skills/do"
touch "$TMPDIR_TEST/fakehome/.claude/skills/do/existing-file"
cp "$SCRIPT_DIR/install.sh" "$TMPDIR_TEST/"
if output=$(HOME="$TMPDIR_TEST/fakehome" bash "$TMPDIR_TEST/install.sh" 2>&1); then
  if [ -d "$TMPDIR_TEST/fakehome/.claude/skills/do.bak" ] && [ -L "$TMPDIR_TEST/fakehome/.claude/skills/do" ]; then
    pass "directory backed up and symlink created"
  else
    fail "backup or symlink missing"
  fi
else
  fail "install.sh exited non-zero: $output"
fi
rm -rf "$TMPDIR_TEST"

echo ""
echo "=== Structure validation tests ==="

# Test: SKILL.md has required frontmatter
echo "[6] SKILL.md has valid frontmatter"
if head -1 "$SCRIPT_DIR/skills/do/SKILL.md" | grep -q "^---$"; then
  if grep -q "^name: do$" "$SCRIPT_DIR/skills/do/SKILL.md"; then
    pass "SKILL.md frontmatter valid"
  else
    fail "SKILL.md missing 'name: do' in frontmatter"
  fi
else
  fail "SKILL.md missing frontmatter delimiter"
fi

# Test: plugin.json is valid JSON with required fields
echo "[7] plugin.json is valid JSON with required fields"
if python3 -c "
import json, sys
d = json.load(open('$SCRIPT_DIR/.claude-plugin/plugin.json'))
assert 'name' in d, 'missing name'
assert 'version' in d, 'missing version'
assert 'description' in d, 'missing description'
" 2>/dev/null; then
  pass "plugin.json valid"
else
  fail "plugin.json invalid or missing required fields"
fi

# Test: Config schemas match between SKILL.md and README.md
echo "[8] Config schemas consistent between SKILL.md and README.md"
SKILL_FIELDS=$(grep -oE '(configVersion|maxIterations|maxCodeReviewIterations|skipReviewThreshold)' "$SCRIPT_DIR/skills/do/SKILL.md" | sort -u)
README_FIELDS=$(grep -oE '(configVersion|maxIterations|maxCodeReviewIterations|skipReviewThreshold)' "$SCRIPT_DIR/README.md" | sort -u)
if [ "$SKILL_FIELDS" = "$README_FIELDS" ]; then
  pass "config fields consistent"
else
  fail "config field mismatch between SKILL.md and README.md"
fi

# Test: Prompt templates have required placeholders
echo "[9] Prompt templates have required placeholders"
PLAN_OK=true
CODE_OK=true
for placeholder in '{TASK}' '{PLAN}' '{CONTEXT}'; do
  grep -q "$placeholder" "$SCRIPT_DIR/skills/do/prompts/plan-review.md" || PLAN_OK=false
done
for placeholder in '{TASK}' '{PLAN}' '{DIFF}'; do
  grep -q "$placeholder" "$SCRIPT_DIR/skills/do/prompts/code-review.md" || CODE_OK=false
done
if $PLAN_OK && $CODE_OK; then
  pass "all prompt placeholders present"
else
  fail "missing placeholders — plan-review: $PLAN_OK, code-review: $CODE_OK"
fi

# Test: All phases present in SKILL.md
echo "[10] All 6 phases present in SKILL.md"
PHASES_FOUND=0
for phase in "Phase 1: PLAN" "Phase 2: ANALYZE" "Phase 3: APPROVE" "Phase 4: IMPLEMENT" "Phase 5: QUALITY" "Phase 6: PRESENT"; do
  grep -q "$phase" "$SCRIPT_DIR/skills/do/SKILL.md" && PHASES_FOUND=$((PHASES_FOUND + 1))
done
if [ "$PHASES_FOUND" -eq 6 ]; then
  pass "all 6 phases present"
else
  fail "only $PHASES_FOUND/6 phases found"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo "$ERRORS"
  exit 1
fi
