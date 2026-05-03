# Storing your recovery key safely

Your recovery key is the only thing that can restore your encrypted message
history on a new device, after a reinstall, or if you lose the device you set
backup up on. Treat it like the master password for your messages.

## What it does

Your messages are encrypted end-to-end. The keys that decrypt them are
themselves encrypted with your recovery key and stored on the server. Without
the recovery key:

- A new device cannot read your old messages.
- Cross-device verification cannot be re-established from scratch.
- Your message history stays encrypted forever — no one (not Kohera, not your
  homeserver admin) can recover it for you.

## Where to store it

**Recommended:**

- A password manager (1Password, Bitwarden, KeePass, your browser's built-in
  manager). This is the simplest and most reliable option for most people.
- Printed on paper, stored somewhere physically secure (a locked drawer, a
  safe, with other important documents).

**Avoid:**

- Screenshots — they sync to cloud photo libraries in plaintext.
- Unencrypted notes apps (Google Keep, Apple Notes without a per-note lock,
  OneNote, plain `.txt` files in iCloud / Drive / Dropbox). These cache to the
  cloud in a form your provider can read.
- Email to yourself — your inbox is one phishing or breach away from exposing
  the key.
- Chat messages, including to yourself in Kohera or any other app.

## "Also keep a copy on this device"

When you set up backup, you can choose to cache a copy of the key in this
device's secure storage so the app can unlock backup automatically.

**This is a convenience, not a backup.** If you lose the device or wipe it,
the cached copy is gone — that's exactly the failure mode the recovery key
exists to protect against. Always save the key somewhere off-device too.

## If you lose your key

Your encrypted message history on the server stays encrypted and unreadable.
You can sign back in and continue using Kohera, but old messages on rooms
you've left, or on devices you no longer have, won't be recoverable.

You can set up a new chat backup at any time — it will protect future
messages, but it can't reach back and decrypt the old ones.
