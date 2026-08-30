# HouseHolder MVP Plan

## Product goal

A privacy-first household butler for two adults sharing household knowledge. Input should be low-friction: photo, voice, or text. Llama 3.2 3B Instruct runs locally and converts natural language into validated structured actions.

## V1 scope

### Inputs
- Photo: on-device OCR, initially optimized for school timetables.
- Voice: platform speech-to-text, then normal text pipeline.
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

## Non-goals for V1
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

### M1 — Local household MVP
- Child/schedule format.
- Shopping/todo formats.
- CRUD FamilyActions.
- Query pipeline through local Llama gateway.
- Basic Flutter screens.

### M2 — Photo + voice
- OCR adapter and timetable import preview.
- Speech-to-text adapter.
- Confirmation UI before imported data is committed.

### M3 — Shared household
- Per-device append-only event log.
- Drive transport adapter.
- Hash/baseHash optimistic concurrency.
- Deterministic merge and conflict UI.
- Semantic merge proposals for unresolved conflicts.

### M4 — Shopping assistant
- Web search provider contract.
- MerchantOffer format.
- Product normalization/deduplication.
- Shipping-aware basket optimizer.
- Purchase-link handoff.

## MVP acceptance examples

1. Photograph a timetable, review parsed classes, confirm, then ask: `明天小孩有什麼課？`
2. Say: `記得買牛奶、雞蛋和衛生紙`, then another household member sees the synchronized list.
3. Both devices edit different fields offline and merge automatically after reconnecting.
4. Same-field conflicts are not silently overwritten.
5. Ask for shopping comparison and receive one-stop vs lowest-delivered-total plans with source purchase links.
6. Add a declarative Skill/Format without modifying the core assistant orchestrator.
