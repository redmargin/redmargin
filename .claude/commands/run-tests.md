---
description: Run tests ONE AT A TIME. Update logs IMMEDIATELY after each test. Fix failures before moving on.
---

# Test Runner

Run tests ONE AT A TIME. Update logs IMMEDIATELY after each test. Fix failures before moving on.

## When This Activates

- After implementing a feature or fix
- When user mentions tests or testing
- When user asks to verify something works

## What to Run

Determine tests from (in order):
1. Explicit argument (e.g., "run PreferencesTests")
2. Context from conversation
3. No argument, no context: run full suite

## Process

### Step 1: List Tests
```bash
xcodebuild test -scheme Redmargin -destination 'platform=macOS' -list-tests 2>&1 | grep "Test Case"
```

### Step 2: Run Each Test ONE BY ONE

For EACH test individually:

1. **Run it:**
```bash
xcodebuild test -scheme Redmargin -destination 'platform=macOS' -only-testing:RedmarginTests/TestClassName/testMethodName
```

2. **Update `Tests/TEST_LOG.md` IMMEDIATELY:**
   - Update "Latest Run" section with date, command, status
   - Update the test's row in the appropriate table (status, duration, timestamp)
   - If test was added/fixed/renamed, add a note to Notes section

3. **If FAILED:**
   - STOP
   - Investigate and fix the failure
   - Re-run the same test
   - Do NOT proceed until it passes

4. **If PASSED:**
   - Continue to next test

### Step 3: JavaScript Tests
```bash
cd WebRenderer && npm test
```

## Rules

- **ONE test at a time** - never batch
- **Log update after EVERY run** - not at the end, not in batches
- **Fix before proceeding** - no skipping failures
- **No "pre-existing" excuses** - all failures are your responsibility to fix
- **Show actual output** - don't summarize or hide errors
- **Never pipe through head/tail** - show full output
- **No mocks** - use real file system with temp directories
