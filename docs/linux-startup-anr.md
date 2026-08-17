# Linux startup "not responding" (rendering / embedding causes)

This documents a class of startup stalls reported on Linux (notably Fedora 42)
that are **not** caused by the Matrix SDK usage and should be triaged separately
from sync / E2EE startup work.

## Symptoms

On startup the desktop shows an OS-level "…is not responding" modal, and the
logs include one or more of:

```
(io.github.quantumheart.kohera:…): Atk-CRITICAL …: atk_socket_embed: assertion 'plug_id != NULL' failed
Gdk-Message: Unable to load  from the cursor theme
[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impimpeller.cc(…)] Using the Impeller rendering backend (OpenGLESSDF).
```

These come from the Flutter GTK embedder / ATK / cursor-theme / Impeller stack,
not from Matrix sync or E2EE. They can independently contribute to the
"not responding" modal even when sync is healthy.

## Why it is separate from the SDK

- The Matrix SDK's SQLite store already runs in a background isolate
  (`databaseFactoryFfi` from `sqflite_common_ffi`, not the `NoIsolate`
  variant), so DB I/O does not block the UI thread.
- The remaining main-isolate cost during startup is the post-first-sync E2EE
  burst (key scan / key recovery); that is addressed cooperatively in
  `ChatBackupService.requestMissingRoomKeys` (batched yields).
- The ATK/cursor/Impeller lines are produced before/around window
  construction and have no Matrix dependency.

## Mitigations to try (in order)

1. **Ensure a cursor theme is installed.** `Gdk-Message: Unable to load  from
   the cursor theme` (note the empty name) indicates the active cursor theme
   resolves to nothing. Install/fill a theme, e.g.:
   ```sh
   sudo dnf install adwaita-cursor-theme
   gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
   ```
   An empty cursor theme is enough on its own to trigger the
   `atk_socket_embed: plug_id != NULL` assertion on some GTK/Flutter builds.

2. **Disable Impeller on Linux (force Skia).** Impeller's GLES-SDF backend is
   the one named in the log. Run with Impeller off to isolate it:
   ```sh
   flutter run -d linux --no-enable-impeller
   ```
   or for a release bundle set the embedder flag
   `FLUTTER_ENGINE_SWITCH_ENABLE_IMPELLER=false` / pass
   `--enable-impeller=false` to the engine. If the stall disappears, Impeller
   GLES is the culprit.

3. **Try the Impeller Vulkan backend instead of GLES.** If Impeller must stay
   on, Vulkan is far more stable on Fedora/Wayland than OpenGLES-SDF:
   ```sh
   flutter run -d linux --enable-impeller --impeller-backend=vulkan
   ```

4. **Check Wayland vs X11.** Some ATK/plug issues are Wayland-specific; running
   under XWayland (`GDK_BACKEND=x11`) can confirm whether it is a Wayland
   embedder bug.

## Related

- Issue #991 "Startup on Linux Fedora 42 Stalls" — the sync-timeout and
  key-scan-yield changes address the Matrix-side contribution; this document
  covers the orthogonal rendering/embedding contribution.