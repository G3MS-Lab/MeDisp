# MeDis UI

MeDis uses a calm blue health companion theme. The existing blue brand remains, with dark text, an off-white page background, and white surfaces with thin borders. Color supplements labels and icons; it never carries a status alone.

## Foundation

- `lib/theme/medis_theme.dart` owns colors, spacing, radii, typography, component themes, and focus/disabled styles.
- Noto Sans Thai is bundled in `assets/fonts` under the included SIL Open Font License. It is available offline. Flutter uses the Thai locale for Material dialogs and word boundaries.
- Body text is 16 px with a 1.55 line height. Key medication and form labels use 18–20 px. Keep text scalable; avoid fixed-height text containers and truncating instructions or drug names.
- Spacing follows 4, 8, 12, 16, 20, 24, 32. Page padding is 20. Inputs use a 12 px radius; cards use 16; dialogs/sheets use 24.
- Primary blue is for the next action. Green means completed/available, amber means waiting/attention, and red means errors/destructive actions. Scheduled and PRN cards share the same blue visual language.

## Shared components

- `MeDisAppBar`: consistent secondary-page title, automatic back navigation, optional actions.
- `MeDisPageHeader`: main-page title and supporting text.
- `MeDisSection`: grouped form and detail content.
- `MeDisEmptyState`: icon, explanation, and optional next action.
- `MeDisNotice`: inline supporting/error message with an icon.
- `MeDisMedicationCard`: shared header, expansion, spacing, and action layout for scheduled and PRN medication. PRN shows dose, symptom, minimum interval, and daily limit once each.
- `MeDisSelectionTile`: large selectable rows for medication type choices.
- `MeDisImageCard`: image preview and an optional compact image picker; `MedicationVerifyImage` adds medication-specific copy.
- `SlideToConfirm`: thick labeled track shared by medication unlock, receiving medication, intake verification, data saves, and action confirmations. Dragging the thumb to the end confirms; a partial pointer drag resets. Keyboard and screen-reader adjustments can advance to the end, with progress announced as a percentage.

Use the Theme's buttons, inputs, list tiles, cards, chips, sheets, and dialogs before adding local styling. Keep one primary action per group. The bottom navigation labels remain visible in Thai. The web layout uses a fixed 440 × 956 logical viewport matching the iPhone 17 Pro Max display ratio (1320 × 2868). It stays centered and scales down uniformly to fit the browser without reflowing the phone layout. Native apps continue to use the full device screen.

Today reuses the original illustrated banner. The menu places four large destinations in a two-column grid before connection details; narrow screens and large accessibility text switch to one column. Keep menu icons at 44 px and labels at 20 px. Medication forms use large type selectors, meal checkboxes, and quantity steppers instead of compact menus.

## Feedback and verification

Form errors appear next to the field. Async actions disable repeat submissions and show progress; saves show a confirmation message. Empty collections explain how to add data. Destructive removal and sign-out use confirmation dialogs with a final slide; removal uses the error color. Profile edits, reminder settings, and symptom records also commit through a slide. Opening profile-edit and new-symptom forms first uses the same slide-unlock confirmation as medication forms. Receiving scheduled or PRN medication starts with a slide, shows the medicine verification dialog, then records the intake only after the final slide. Navigation, value selection, and cancellation remain direct taps. Medication verification, schedule rules, persistence, and inventory limits remain in the existing application/domain layer.

`test/ui_layout_test.dart` renders all screens at 320, 430, and 640 px. The narrow case uses 1.4× text. It loads the real Thai font and scrolls through each page to catch hidden overflows. Set `MEDISP_CAPTURE_UI=1` to save rendered screenshots to `build/ui-review/`.
