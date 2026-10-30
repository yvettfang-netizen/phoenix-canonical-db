# M2 Architecture — Lead & Acquisition

M2 extends the existing CRM Lead authority. A Lead may remain unidentified; it never auto-creates or auto-merges Person, Family or Client records.

- Controlled lifecycle: NEW → CONTACTED → QUALIFIED → CONVERTED/LOST/DISQUALIFIED. LOST, DISQUALIFIED, CONVERTED and MERGED are terminal through this API.
- Lead creation records immutable First Touch with Compass, source system, campaign and attribution-model version. Conversion Touch is a distinct one-time record.
- Identity matching continues to use the existing pending, distinct-reviewer verification and revocation lifecycle.
- Deduplication is two-stage: evidence-digest candidate proposal, distinct-principal review, then manual merge. Merge reversal restores the source Lead’s prior state while retaining both decisions.
- Referral records point to an active Partner relationship and Lead Source and append independent events.

All tables reuse canonical Person/Family/Client/Partner/Principal keys and the one-use database context path.
