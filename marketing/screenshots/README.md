# App Store screenshots

English, 1320 × 2868 (iPhone 6.9"), five slides, in `out/en/`.

1. Capture clean screens from the simulator (9:41 status bar, demo data):
   `./launch.sh en` then navigate and run `./capture.sh en <home|qr|people|person|followups>` → `raw/en/`.
   (`raw/uz` and `raw/ru` are kept for localised sets later.)
2. Edit captions and layout in `screenshot.html` (`?lang=en&slide=1`, `?lang=en&grid=1` for an overview).
3. Render: `./export.sh en` → `out/en/1…5.png` (headless Chrome).

Device frame: Apple's iPhone 17 Pro, Silver (`frames/`), screen opening at x 72, y 69.
Recapture the QR slide once the real domain replaces `tanishly.app`.
