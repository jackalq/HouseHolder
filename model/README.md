# Local model pack

Target model: `Llama-3.2-3B-Instruct`

Do not commit model weights to Git.

## Android MVP runtime

The Android MVP is pinned to ExecuTorch `1.3.1` while the runtime integration is validated on physical devices.

HouseHolder expects the installed model pack under Android app-private storage:

```text
<filesDir>/model-pack/
├─ llama32-3b-instruct.pte
└─ tokenizer.bin        # preferred
   # or tokenizer.model
```

The APK intentionally does not bundle the multi-GB model. `LocalLlamaEngine` reports whether both model and tokenizer artifacts are present before inference begins.

The application should eventually install model packs through a dedicated installer that performs:

- free-space check
- download to a temporary file
- expected size check
- SHA-256 checksum verification
- atomic rename into `model-pack/`
- model/version manifest update
- delete/reinstall support

Until the installer exists, a development build can place the artifacts into the app-private `model-pack` directory through development tooling.

## Runtime contract

Flutter `LocalLlamaGateway` calls the Android method channel `family_butler/llm`:

- `isModelReady`
- `modelStatus`
- `generate`
- `stop`

`generate` is run off the Android UI thread. Generated tokens are accumulated natively and returned to Flutter only after ExecuTorch reports completion. The application layer still treats the result as a draft: schema validation and user confirmation happen before household data is mutated.

## Export / quantization

Use the export workflow matching the pinned ExecuTorch release and produce a mobile-quantized `.pte` compatible with the LLM runner. Start with XNNPACK for broad Android compatibility. Hardware-specific backends can be evaluated after the CPU/XNNPACK vertical slice works reliably.

Llama 3.2 3B requires physical-device memory and latency testing; supported devices must be determined empirically rather than assumed.
