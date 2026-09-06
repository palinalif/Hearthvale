# Physical Thor M0 checklist

All physical-device items start **not run**. Record actual firmware/Android version, renderer, resolution, fan/performance mode, power state, controller type, and test duration. Omit device serial numbers and other identifiers from reports.

1. Install the debug APK as an update, launch it cold, and capture Android logs. Verify no missing native library, Vulkan, shader, or script errors. Repeat with the release-mode APK; both must actually load on ARM64.
2. Use only the built-in controller: move cursor, orbit/tilt, zoom, adjust cursor altitude and brush size, switch add/remove. Inspect the tunnel and its intact roof.
3. Preview an edit and cancel it. Commit a small removal, add some terrain, then undo and redo. Check the visible terrain and native data status agree after settling.
4. Open pause, use controller focus to save, change terrain, reload, and verify the saved result. Quit and fully restart the app, reload again, and compare. No touch, mouse, or operating-system keyboard.
5. Disconnect an external pad during a preview; confirm it cancels and world input stops. Reconnect and resume without an accidental edit. Suspend/resume during preview and after saving; ensure the checkpoint remains valid.
6. Run the repeatable fixture in Mobile and Compatibility where supported. Capture frame pacing, draw/primitive counts, edit/save costs, and Android process-memory observations. Record crashes and stalls. Do not extrapolate this small patch to a full village or claim 60 fps from a brief counter reading.
7. If available, connect TV/dock and an external pad. Verify one landscape gameplay surface, readable focus/UI, external-pad route, display attach/detach, audio routing, and return from Android settings. Otherwise mark TV checks **not run**.

Return logs/screenshots and notes on cursor precision, camera comfort, tunnel readability, and any actions that needed touch. M1 starts only after the M0 handoff has been reviewed and its required evidence accepted.
