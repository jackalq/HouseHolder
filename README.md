# Family Butler

Privacy-first household assistant for Android and iOS with an on-device Llama 3.2 3B Instruct model.

## Goals

- Store and query children's class schedules.
- Track shopping items and household todo items.
- Let two family members share the same household state.
- Keep ordinary household data usable offline.
- Run the assistant locally on-device where practical.
- Add shopping comparison/cart integrations through explicit provider adapters.

## Recommended stack

- UI: Flutter
- Local LLM: PyTorch ExecuTorch + Llama 3.2 3B Instruct, quantized for mobile
- Local data: SQLite (production adapter)
- Sync: encrypted household document/event log in a shared Google Drive folder
- Shopping: provider interface; search/compare/cart actions require explicit user confirmation

## Repository status

This is an MVP starter/scaffold. It includes:
- Flutter domain/UI starter
- a platform-channel contract for local LLM inference
- Android Kotlin ExecuTorch adapter example
- iOS Swift ExecuTorch adapter example
- family data schema
- Google Drive sync design
- shopping provider design
- export notes for generating the mobile `.pte` model

The large model files are intentionally NOT committed to Git. Keep them under `model/` locally or download/install them as an app model pack.

## Architecture

```text
Flutter UI
   |
   +-- FamilyRepository -------- SQLite / local JSON
   |
   +-- AssistantOrchestrator
   |      |
   |      +-- LocalLlamaGateway -- Flutter MethodChannel
   |                                   |
   |                       +-----------+-----------+
   |                       |                       |
   |                 Android/Kotlin           iOS/Swift
   |                 ExecuTorch LLM          ExecuTorchLLM
   |
   +-- SyncProvider ---------- Google Drive shared folder
   |
   +-- ShoppingProvider ------ retailer/search adapters
```

## Important model note

Llama 3.2 3B is suitable for mobile only after quantization and device-specific validation. Treat the model as an installable local model pack rather than placing multi-GB weights directly in source control.

## MVP assistant commands

Examples:
- `明天小孩有什麼課？`
- `星期三幾點要上英文？`
- `幫我記得買牛奶、雞蛋和衛生紙`
- `新增待辦：星期五繳學費`
- `列出還沒買的東西`
- `把買牛奶標記完成`

For household state mutation, the LLM should produce a structured action. The application validates and applies the action; the model never writes storage directly.

## Next implementation steps

1. Create the Flutter project shell (`flutter create .`) and merge `lib/`.
2. Add the current ExecuTorch Android/iOS runtime dependencies.
3. Export/quantize Llama 3.2 3B Instruct to `.pte`.
4. Replace `MemoryFamilyRepository` with SQLite.
5. Implement Google sign-in + Drive shared-folder sync.
6. Implement retailer-specific shopping providers only where API/terms permit.
