# Local model pack

Target model: `Llama-3.2-3B-Instruct`

Do not commit model weights to Git.

Expected runtime artifacts:

```text
model/
  llama32-3b-instruct.pte
  <tokenizer artifact>
```

Use the pinned ExecuTorch release's current Llama export workflow and mobile quantization. Validate on physical Android and iOS devices.

The app should support model installed/not-installed state, version, checksum verification, free-space checks, and model deletion/reinstallation. A downloadable model pack is preferable to embedding multi-GB weights directly into every APK/IPA.
