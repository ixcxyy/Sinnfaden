# Prompt and teaching quality check — 20 October 2026

## Scope and results

Checked the installed 0.4.4/build 9 with its existing connected ChatGPT account. Four new live requests covered the scenarios below; the email case used the real result generated during the preceding installation check. These were synthetic examples, with no paid API key or external test data. No visual design or tutor instructions changed.

The review checked whether the coach preserves the user's intent, language, facts and limits; asks only for meaningful missing information; produces a usable prompt rather than executing it; and explains actual changes without overstating learning success.

| Scenario | Observed result | Assessment |
| --- | --- | --- |
| Friendly appointment email | Finished prompt visible with recipient, existing appointment and desired-change fields. Explanation connected those details to the email. An irrelevant practice answer received reflective feedback without a success claim. | Passed; no invented recipient or appointment. |
| Weather versus climate for an adult beginner; German, 120-word limit, one everyday example, two questions, no jargon | `already_good`, exact original preserved. Feedback correctly identified audience, language, length and structure. Optional practice asked for a relevant everyday situation. | Passed; no unnecessary rewrite or invented weakness. |
| “Mach das besser.” | One clarification asked which prompt to improve, with no fabricated finished prompt. | Passed. |
| Clarification supplied beginner Spanish, 15 minutes/day, four weeks, no paid apps | A practical daily learning-plan request retained the supplied facts and limits. Its explanation identified the useful addition: an actionable result and daily exercises. | Passed; clarification completed successfully. |
| English vegetarian dinners for two, three evenings, €25 total, no mushrooms or oven, 20 minutes/meal, only existing ingredients | English preserved, all limits retained. A required pantry/quantity field and a feasibility check avoided inventing ingredients or silently relaxing constraints. | Passed; additions were relevant to the harder planning task. |

These samples support the observed behaviors, not a guarantee that every future model response will be correct. The open-ended practice feedback remains a conservative local reflection aid, not semantic grading.

## Reproduced defects and fixes

The fixed “Eine Antwort prüfen” lesson says the source appointment is Tuesday at 16:00 and the answer incorrectly says Wednesday at 16:00.

1. **Wrong time accepted:** “Bitte korrigiere Mittwoch auf Dienstag um 16:30.” received “Das passt zur Aufgabe” and independent credit. Time parsing required the word “Uhr” and missed colon-only times. It also missed minutes in “16 Uhr 30” and incorrectly rejected the valid “16.00 Uhr”.
2. **Reversed correction accepted:** “Bitte ersetze Dienstag mit Mittwoch; 16 Uhr bleibt.” also received positive feedback. The wrong-direction guard omitted “mit” and “gegen”.
3. **Old grades survived reopening:** saved incorrect success flags continued advancing the lesson. Loading now refreshes derived feedback for this unchanged fixed exercise, while preserving answers, IDs, timestamps, help/solution flags, drafts and unrelated lessons. Loading itself never rewrites the original file.

The time check now recognizes colon times, dotted times with “Uhr”, and minutes after “Uhr”. Dotted dates are not treated as times. Incorrect day directions are rejected for the reproduced phrasings. These are bounded checks for the fixed lesson, not a general German-language parser.

## Validation

- Baseline: 179 Swift tests passed.
- Two new grading tests failed before the fix with 13 assertions; the persistence test failed with four behavior assertions. The persistence fixture uses a whole-second timestamp to avoid unrelated JSON date precision noise.
- After the fixes: **182 Swift tests**, **17 relay tests**, and **5 release-staging tests** passed, for **204 total**.
- Release compilation and deep/strict code-sign verification passed.
- In the rebuilt native app, both incorrect answers now show “Noch nicht ganz” with the relevant correction. “Bitte ersetze Mittwoch mit Dienstag; 16.00 Uhr bleibt.” receives the correct positive feedback.
- Manual diff review checked preservation of answers and help provenance, time/date boundaries, positive controls, and unchanged UI files. The local graph was refreshed.

Local evidence is under `Artifacts/prompt-quality/`: live scenario text, `wrong-time-feedback-before.txt`, `wrong-day-feedback-before.txt`, corresponding after files, `correct-feedback-after.txt`, regression failure logs, `tests-after.log`, `relay-tests.log`, `release-tests.log` and `build.log`.

The fixes were pushed as `7ef9b36`. **0.4.5/build 10 is installed and published**, after a successful separate-copy update. The actual saved incorrect attempts now show corrected feedback in the Applications copy, with its existing ChatGPT connection restored. See [release verification](RELEASE-0.4.5.md).
