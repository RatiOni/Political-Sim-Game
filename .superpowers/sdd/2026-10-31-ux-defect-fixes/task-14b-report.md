# Task 14b report
Measured at 1280x720 after _resize_layout (min width): Identity 85, DateLabel 120, Budget 92, Legislation 115, Diplomacy 112, Records 100, Play 116, SpeedControls 236 (5x44 touch targets), SoundControl 72 (slider already hidden), Save 72, Load 72; 10 gaps x 8 = 80. Header 1272; app 1320 = header + 2x24 root margin.
Fix (app.gd _resize_layout, compact only): header separation 8 -> 6, Margin left/right 24 -> 12. Header 1252, app 1276. No control hidden or shrunk.
Test: tests/ui/test_header_fits.gd (failed at 1320 first, passes at 1276).
Stale vertical_slice_test expectations (intent kept): Save/Load buttons and the load shortcut now open a slot dialog (save-slots commit), so the test calls scene._do_save()/_do_load() directly; the dialog is covered by test_save_dialog.
Results: all tests/ui/test_*.gd, tests/map/test_pixel_map.gd, vertical_slice_test pass (exit 0).
