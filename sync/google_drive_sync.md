# Google Drive household sync

A folder is created by Adult A and shared with Adult B.

```text
FamilyButler/
  manifest.json.enc
  events/
    device-a/
      <timestamp>-<uuid>.json.enc
    device-b/
      ...
```

## Encryption

Generate a random household key on the first device. Encrypt every payload before Drive upload with authenticated encryption. Exchange the household key through a deliberate pairing flow. Never store the raw household key in Drive beside the ciphertext.

## Sync algorithm

1. Write local mutation to local DB/event log.
2. Encrypt event.
3. Upload event using a unique immutable filename.
4. List unseen events from other devices.
5. Download, decrypt, and apply events deterministically.
6. Update the local seen-event cursor.

This avoids both phones repeatedly replacing one shared database file.
