# HouseHolder MVP Plan

## Product goal

A privacy-first household butler for two adults sharing household knowledge. Input should be low-friction: photo, voice, or text. Llama 3.2 3B Instruct runs locally and converts natural language into validated structured actions.

## First MVP platform

The first executable MVP targets **Android only**.

Flutter remains the application framework so the shared Dart/domain layer can later be reused for iOS, but all platform-specific MVP integration work is Android-first:
- Android on-device OCR.
- Android speech-to-text.
- Android ExecuTorch / local Llama integration.
- Android file/storage integration.
- Android Google Drive integration and end-to-end device testing.

The iOS shell and adapters are intentionally postponed until the Android vertical slice is validated.

## V1 scope

### Inputs
- Photo: on-device OCR, initially optimized for school timetables.
- Voice: Android speech-to-text, then normal text pipeline.
- Text: direct conversation/input.

### Household capabilities
- Child profiles and school schedules.
- Shopping list.
- Todo list.
- Query household information conversationally.
- Skill/Format registry so capabilities are declarative and extensible.

### Shared storage
- Hierarchical JSON document store.
- Summary/detail separation.
- Canonical JSON + SHA-256 record hashes.
- Append-only per-device change events.
- Deterministic merge first; semantic merge proposal only for unresolved conflicts.
- Google Drive as the first shared transport/backend.

### Shopping
- Search the web for product offers and purchase links.
- Normalize offers across merchants.
- Optimize a whole shopping basket, not only individual products.
- Strategies include lowest delivered total, lowest one-stop total, and fewest merchants.
- LLM interprets preferences; deterministic code calculates money, shipping, constraints and ranking.
- V1 stops at purchase links/cart handoff. No autonomous checkout.

## Non-goals for the first MVP
- iOS platform integration.
- Autonomous payment or checkout.
- Arbitrary generated executable code for new skills.
- Perfect OCR for every document layout.
- Full CRDT implementation.
- Server-side household database.

## Core rule

Model proposes; application validates and decides.

The model never directly writes files, Drive data, credentials, or shopping carts. It emits typed actions that are validated by schemas and policy before execution.

## Milestones

### M0 — Foundation
- Finalize folder conventions and schemas.
- Implement canonical JSON hashing.
- Implement JSON repository abstraction.
- Implement Skill and Format registries.

### M1 — Android local household MVP
- Generate/complete Android Flutter platform shell.
- Child/schedule format.
- Shopping/todo formats.
- CRUD FamilyActions.
- Query pipeline through Android local Llama gateway.
- Basic Flutter screens.

### M2 — Android photo + voice
- Android on-device OCR adapter and timetable import preview.
- Android speech-to-text adapter.
- Confirmation UI before imported data is committed.

### M3 — Shared household
- Per-device append-only event log.
- Google Drive transport adapter on Android.
- Hash/baseHash optimistic concurrency.
- Deterministic merge and conflict UI.
- Semantic merge proposals for unresolved conflicts.

### M4 — Shopping assistant
- Web search provider contract.
- MerchantOffer format.
- Product normalization/deduplication.
- Shipping-aware basket optimizer.
- Purchase-link handoff.

### M5 — iOS port
- Reuse Dart/domain/JSON/Skill/Format layers.
- Add iOS OCR and speech adapters.
- Add iOS ExecuTorch integration.
- Validate Drive sync interoperability between Android and iOS.

## First Android vertical-slice acceptance target

1. Install and launch HouseHolder on a physical Android phone.
2. Photograph a timetable.
3. Run OCR locally and show the extracted timetable for review.
4. Convert reviewed OCR content into validated ScheduleItems.
5. Confirm and persist them to the hierarchical JSON repository.
6. Ask by text or voice: `明天小孩有什麼課？`
7. Resolve the answer from household data rather than model memory.
8. Add shopping/todo items by voice or text.
9. Persist changes as append-only device events.

## Later MVP acceptance examples

- Another household member sees synchronized data through Google Drive.
- Two Android devices edit different fields offline and merge automatically after reconnecting.
- Same-field conflicts are not silently overwritten.
- Shopping comparison returns one-stop vs lowest-delivered-total plans with source purchase links.
- A declarative Skill/Format can be added without modifying the core assistant orchestrator.
