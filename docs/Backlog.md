# Backlog

This is a lightweight place to collect ideas before they deserve design, code, or a ticket-shaped ceremony. Keep entries short, concrete, and easy to reorder.

## Now

- **Stop transcribing affordance:** For any reason (e.g. if the user starts with the wrong file or wrong language, or thinks there is enough material) it must be possible to stop the transcript and optionally use what there is, restart, or start afresh by loading another file.

- **Progress indicator:** The user must be able to tell how far the transcription, translation, and segmentation process has come.

- **Stabilize lexical annotation units:** Treat semantic/lexical units as the next useful learning layer and the spine of the generated JSON. Each word-like unit should be able to carry surface text, normalized form if needed, Pinyin, IPA, gloss, kind, and later provenance/confidence.
- **Move beyond implementation-time vocabulary:** Replace the `TemporaryChineseGlosses` scaffold with a dynamic lookup path. The tool should no longer depend on hardcoded vocabulary gathered while implementing a sample transcript.
- **Add durable lexical data sources:** Introduce an offline lexical dictionary source, such as CC-CEDICT, behind a small lookup service. Keep room for permanent tool/API-assisted annotation later, but make the local dictionary/cache path reliable enough for offline use.
- **Expand the persistent annotation cache to lexical units:** `LocalAnnotationCache` already persists usable character annotations; extend it so lexical units can persist dictionary lookups, generated readings, user/model corrections, source metadata, and refresh/version information.
- **Stage context-aware phonetics:** Upgrade `ChineseRomanizer` and `MandarinIPAConverter` to consume lexical annotations instead of operating only from raw text. Heteronyms, tone sandhi, neutral tones, and IPA refinement can then improve incrementally through dictionary candidates, local rules, cache entries, and later model/tool-assisted corrections.

## Next

- Define the annotation pipeline boundaries: tokenizer, dictionary lookup, number/date handling, Pinyin selection, IPA conversion, sandhi rules, cache read/write, and optional external annotation.
- Add cache provenance fields: generated locally, supplied by model/tool, corrected by user, imported from dictionary, and timestamp/version.
- Make stale annotation refresh rules explicit. For example, refresh placeholder IPA, but preserve user-corrected IPA.
- Improve the SegmentsReader controls once the data shape settles: per-row visibility for Pinyin, IPA, glosses, character grid, and lexical grid.

## Later

- Add a real dictionary-backed source for Hanzi character glosses, etymology, radicals, stroke data, and components.
- Support richer lexical-unit disambiguation for Chinese compounds, names, numbers, percentages, dates, and domain-specific phrases.
- Add tone sandhi and neutral-tone handling, especially for common forms such as 不, 一, reduplication, and 儿化.
- Decide how German and Romanian IPA should be generated: local rule-based approximation, platform voices, dictionary lookup, or model-assisted annotation.

## Parking Lot

- Consider import/export tools for the annotation cache so useful corrections survive app reinstalls and can be shared between machines.
- Consider a review mode in SegmentsReader where uncertain annotations are visually marked and can be accepted or corrected.
- Consider keeping both broad and narrow IPA if narrow IPA becomes too visually dense for beginner reading.
