# HouseHolder

Android-first privacy-focused family assistant MVP.

## Current MVP capabilities

- Android Flutter application shell.
- On-device Chinese OCR for school timetable photos.
- Timetable review/edit before persistence.
- Android speech recognition with on-device mode when supported.
- Local Llama 3.2 3B through ExecuTorch Android.
- Llama model/tokenizer installation through Android file picker.
- Typed `FamilyAction` validation; the model never writes household data directly.
- Hierarchical JSON/JSONL persistence with canonical SHA-256 content hashes.
- Append-only per-device change events.
- Grounded schedule queries from persisted household data.
- Shopping list and todo CRUD.
- Android shared-folder sync through Storage Access Framework (SAF), suitable for a shared Google Drive folder exposed by the system document provider.
- Deterministic remote-event merge with conflict inbox and user-confirmed conflict resolution events.
- Shopping comparison contracts, normalized merchant offers, deterministic shipping-aware basket optimization, and external purchase-link handoff.

## Android build

The repository CI uses Flutter stable and runs:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

A successful GitHub Actions run uploads the debug APK as the `householder-debug-apk` artifact.

## Local model pack

The model is intentionally not committed to the repository. Install the following through the app UI:

- `llama32-3b-instruct.pte`
- matching tokenizer (`tokenizer.bin` or supported tokenizer model)

See `model/README.md` and the export helper under `scripts/` for the ExecuTorch model-pack path.

## Household sync

On each Android phone:

1. Open **家庭同步**.
2. Choose the same shared HouseHolder folder through Android's system folder picker.
3. Grant persistent read/write access to that folder only.
4. Tap **立即同步**.
5. Resolve any same-field conflicts explicitly in the conflict inbox.

The sync model uses one append-only event stream per device, optimistic `baseHash` checks, deterministic field merge, and explicit user confirmation for ambiguous conflicts.

## Shopping comparison

HouseHolder does not store web-search API secrets in the APK. A stateless offer-search endpoint can return normalized `MerchantOffer` records; the Android app performs money, shipping-threshold, merchant-count, and basket-plan calculations locally.

Supported strategies:

- lowest delivered total
- lowest one-stop total
- fewest merchants

V1 stops at external purchase links. No autonomous checkout or payment.

## Core rule

**Model proposes; application validates and decides.**
