# HouseHolder

Privacy-first household butler. The first executable MVP targets **Android** and uses Flutter for the shared application/domain layer.

## First MVP goal

The first vertical slice is deliberately narrow and testable:

```text
Android phone
  -> photograph school timetable
  -> on-device OCR
  -> timetable preview/correction
  -> local Llama 3.2 3B proposes ScheduleItems
  -> schema validation + user confirmation
  -> hierarchical JSON repository
  -> ask: "明天小孩有什麼課？"
  -> answer from household data
```

Voice and text enter the same assistant pipeline. Shopping and todo actions use the same typed FamilyAction boundary.

## Architecture rules

- **Model proposes; application decides.** The model never directly mutates household files, Drive data, credentials, carts or payments.
- Household persistence is a **hierarchical JSON document store**, not a shared SQLite database.
- Summary/index documents are separated from details and can be rebuilt.
- Changes become **append-only per-device events**.
- Canonical JSON + hashes/baseHash provide optimistic concurrency.
- Merge order is deterministic merge first, then an LLM semantic *proposal* only for unresolved ambiguity.
- Skills and Formats are declarative/versioned so Butler capabilities can expand without rewriting the orchestrator.

## Android-first stack

- UI/application: Flutter
- Local LLM: PyTorch ExecuTorch + quantized Llama 3.2 3B Instruct
- OCR: Android on-device adapter through `householder/ocr`
- Speech: Android speech-to-text adapter through `householder/speech`
- Local data: hierarchical JSON/JSONL files
- Sync: encrypted append-only household events over Google Drive (later MVP milestone)
- Shopping: web/provider adapters + deterministic basket optimizer

Large model files are intentionally not committed to Git. Treat the `.pte` model and tokenizer as an installable model pack.

## Current code

- `lib/main.dart` — Android-first Flutter home shell.
- `lib/assistant/local_llama_gateway.dart` — local LLM platform-channel contract.
- `lib/assistant/assistant_orchestrator.dart` — common text/speech/image-OCR entry point.
- `lib/platform/ocr_gateway.dart` — OCR document/block contract including bounds.
- `lib/platform/speech_gateway.dart` — speech recognition contract with on-device capability check.
- `lib/storage/json_repository.dart` — hierarchical JSON + JSONL document repository.
- `lib/storage/canonical_json.dart` — stable canonical representation for hashing.
- `lib/storage/change_event.dart` — append-only change event model.
- `lib/skills/skill_definition.dart` — declarative Skill registry contract.
- `formats/` and `skills/` — versioned Format/Skill definitions.
- `docs/MVP_PLAN.md` — Android MVP milestones and acceptance target.

## MVP sequence

1. Complete Android Flutter platform shell.
2. Wire Android OCR and image selection/camera input.
3. Build timetable import preview + validation.
4. Persist confirmed schedule data in hierarchical JSON.
5. Wire local Llama through ExecuTorch and structured FamilyActions.
6. Add Android speech input.
7. Add per-device event log + merge engine.
8. Add Google Drive transport.
9. Add shopping search/normalization/basket optimization.
10. Port shared layers to iOS after the Android slice is validated.
