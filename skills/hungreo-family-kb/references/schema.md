# Family profile schema (draft)

## Required

- Chat_ID
- Member_ID
- Display_Name
- Age
- Sex

## Optional

- Chronic_conditions
- Current_medications
- Allergies
- Notes / constraints

## Storage (current decision)

- Excel file on Google Drive, shared read/write with family; Hưng controls.
- OpenClaw should treat it as source-of-truth but never expose raw file publicly.
