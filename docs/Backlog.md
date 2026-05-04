# Backlog

This is a lightweight place to collect ideas before they deserve design, code, or a ticket-shaped ceremony. Keep entries short, concrete, and easy to reorder.

## Now

- Character IPA is deterministic pinyin-to-IPA, not a full phonology engine. It does not yet handle tone sandhi, contextual pronunciation, or heteronym correction beyond the pinyin supplied upstream.
- Character-level English glosses are still a small hand-built scaffold. Replace this with an independent character annotation source rather than fragmenting sentence translations.
- Semantic/lexical units are the next useful learning layer: surface text, pinyin, IPA, gloss, and possibly grammatical role per word-like unit.

## Next

- Expand the local annotation cache beyond character units so lexical units can persist corrected pinyin, IPA, glosses, and source metadata.
- Add cache provenance fields: generated locally, supplied by model, corrected by user, imported from dictionary, and timestamp/version.
- Make stale annotation refresh rules explicit. For example, refresh placeholder IPA, but preserve user-corrected IPA.
- Improve the SegmentsReader controls once the data shape settles: per-row visibility for Pinyin, IPA, glosses, character grid, and lexical grid.

## Later

- Add a real dictionary-backed source for Hanzi character glosses, etymology, radicals, stroke data, and components.
- Support lexical-unit disambiguation for Chinese compounds, names, numbers, percentages, dates, and domain-specific phrases.
- Add tone sandhi and neutral-tone handling, especially for common forms such as 不, 一, reduplication, and 儿化.
- Decide how German and Romanian IPA should be generated: local rule-based approximation, platform voices, dictionary lookup, or model-assisted annotation.

## Parking Lot

- Consider import/export tools for the annotation cache so useful corrections survive app reinstalls and can be shared between machines.
- Consider a review mode in SegmentsReader where uncertain annotations are visually marked and can be accepted or corrected.
- Consider keeping both broad and narrow IPA if narrow IPA becomes too visually dense for beginner reading.
