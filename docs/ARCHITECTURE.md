# Architecture

## Principle: model proposes, app decides

The local model is a natural-language parser and planner. It does not get direct database, Drive, or shopping credentials.

1. User enters natural language.
2. App builds minimal context from local household data.
3. LLM returns an answer or structured `FamilyAction`.
4. App validates the action.
5. Read-only actions execute immediately.
6. State-changing actions are applied to local storage.
7. Purchase/cart actions require explicit confirmation.
8. Sync runs after a local state change.

## Core bounded contexts

- Schedule: child, weekday, time, activity, location, note.
- Shopping: item, quantity, unit, brand, target price, status.
- Todo: title, due time, assignee, status, note.
- Household: household ID and members.

## Data safety

- Store only minimum required family information.
- Encrypt cloud payloads before upload.
- Keep OAuth tokens in Keychain/Keystore.
- Do not send family data to remote LLM services unless explicitly enabled.
- Keep a local audit trail for sync conflicts.

## Sync

For two-person sharing, use an append-only encrypted event log in a shared Google Drive folder instead of overwriting one SQLite database file. For a larger multi-user product, migrate to a realtime synchronization database.
