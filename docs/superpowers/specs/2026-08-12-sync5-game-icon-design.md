# Sync5 Game Icon Design

## Goal

Create a simple, striking launcher icon for Sync5 that communicates both its
poker-deckbuilder gameplay and cyberpunk live-performance identity at a glance.

## Approved Direction

Use two unmistakable playing cards as the dominant emblem, fanned with enough
overlap to preserve one compact silhouette. Show one large spade and one large
heart on the exposed card faces. A smaller vinyl record sits behind the cards
at the lower right as a secondary live-performance cue.

This revision explicitly fixes the first version's failure: the oversized
record and pulse line made the icon read as a music game before it read as a
card game. The third revision also fixes the second version's presentation
failure: a pure-black outer field blended into surrounding UI and made the art
look like a floating logo instead of a complete App Store icon.

## Composition

- Square 1:1 master artwork, composed to remain legible inside rounded launcher
  masks.
- Use an opaque, full-bleed dark violet-to-blue gradient background that remains
  visibly distinct from surrounding black UI all the way to every canvas edge.
- Do not include black outer margins, a floating panel, or a baked outer rounded
  rectangle in the upload master.
- Two fanned, rounded-rectangle playing cards occupy roughly 70 percent of the
  canvas and remain fully recognizable as cards.
- Use pale paper card faces with a large cyan spade and a large magenta heart;
  omit ranks and corner text.
- One glossy black vinyl record occupies roughly 25 percent of the canvas,
  partially hidden behind the lower-right card edge.
- No waveform, pulse line, equalizer, music note, title, letters, numbers,
  characters, UI, border frame, or watermark.

## Visual Language

- Match the project's locked neon-stage art direction.
- Palette: cyan `#1effec`, magenta `#ff328d`, violet `#7642ff`, with restrained
  white-hot highlights.
- Materials: lightly reflective paper card faces with crisp neon rim light;
  glossy black vinyl with restrained grooves and bloom.
- The full-bleed background stays dark but visibly colored. Cyan and magenta
  light may softly illuminate it without creating an empty black moat.
- Render as a polished stylized 3D icon with clean geometry, not a detailed
  illustration or realistic scene.

## Readability Criteria

- The playing cards must read before the record at both full size and 64 px.
- Both the spade and heart must remain recognizable at 64 px.
- After applying an iOS rounded-square mask, no essential part of the cards,
  suits, or record may be cropped.
- The silhouette must not depend on tiny lines, text, or fine texture.
- Cyan and magenta highlights should separate the card edges from the dark
  gradient background without washing out the pale card faces.
- The focal point is the two-card fan; the record is visibly secondary.

## Deliverable

Generate two review artifacts:

- `sync5-game-icon-master-v3.png`: opaque 1024×1024 sRGB upload master with a
  square, unmasked, full-bleed background.
- `sync5-game-icon-ios-preview-v3.png`: the same artwork shown through an iOS
  rounded-square mask for visual approval only; this preview is not uploaded to
  App Store Connect.

After approval, use the square master as the source for Icon Composer or the
Xcode asset catalog.
