# Sync5 Game Icon Design

## Goal

Create a simple, striking launcher icon for Sync5 that communicates both its
poker-deckbuilder gameplay and cyberpunk live-performance identity at a glance.

## Approved Direction

Use two unmistakable playing cards as one fused emblem. The foreground card is
a pale face card with one large cyan spade. The rear card is a dark card back
whose entire back design is built from vinyl-record grooves, a center label,
and a spindle point contained within the rounded rectangle. The music identity
therefore belongs to the deck itself instead of appearing as a separate prop.

This revision explicitly fixes the first version's failure: the oversized
record and pulse line made the icon read as a music game before it read as a
card game. The third revision also fixes the second version's presentation
failure: a pure-black outer field blended into surrounding UI and made the art
look like a floating logo instead of a complete App Store icon. The fourth
revision fixes the remaining collage problem: separate cards and a separate
record looked like three adjacent assets rather than one designed mark.

## Composition

- Square 1:1 master artwork, composed to remain legible inside rounded launcher
  masks.
- Use an opaque, full-bleed dark violet-to-blue gradient background that remains
  visibly distinct from surrounding black UI all the way to every canvas edge.
- Do not include black outer margins, a floating panel, or a baked outer rounded
  rectangle in the upload master.
- Two fanned, rounded-rectangle playing cards occupy roughly 76 percent of the
  canvas and share the same perspective, thickness, overlap, and center of
  gravity.
- The foreground pale card uses one large cyan spade and omits ranks and corner
  text.
- The rear dark card uses concentric vinyl grooves clipped entirely inside its
  card-back rectangle, with a small magenta-violet center label. At most a
  subtle circular highlight may suggest rotation; no separate round disc may
  protrude outside the card silhouette.
- Remove the heart suit so the foreground spade and vinyl card-back center do
  not compete for attention.
- Remove the reflective floor plane and contact reflections; the emblem floats
  cleanly on the full-bleed gradient.
- No waveform, pulse line, equalizer, music note, title, letters, numbers,
  characters, UI, border frame, or watermark.

## Visual Language

- Match the project's locked neon-stage art direction.
- Palette: cyan `#1effec`, magenta `#ff328d`, violet `#7642ff`, with restrained
  white-hot highlights.
- Materials: lightly reflective paper face card and glossy black-vinyl card
  back, both with the same physical card thickness and crisp neon rim light.
- The full-bleed background stays dark but visibly colored. Cyan and magenta
  light may softly illuminate it without creating an empty black moat.
- Render as a polished stylized 3D icon with clean geometry, not a detailed
  illustration or realistic scene.

## Readability Criteria

- The playing cards must read before the record at both full size and 64 px.
- The spade and both rectangular card silhouettes must remain recognizable at
  64 px; the vinyl grooves may simplify into a circular sheen.
- After applying an iOS rounded-square mask, no essential part of the cards,
  suits, or record may be cropped.
- The silhouette must not depend on tiny lines, text, or fine texture.
- Cyan and magenta highlights should separate the card edges from the dark
  gradient background without washing out the pale card faces.
- The focal point is the spade face card; the record identity is discovered in
  the rear card back rather than read as a third object.

## Deliverable

Generate two review artifacts:

- `sync5-game-icon-master-v4.png`: opaque 1024×1024 sRGB upload master with a
  square, unmasked, full-bleed background.
- `sync5-game-icon-ios-preview-v4.png`: the same artwork shown through an iOS
  rounded-square mask for visual approval only; this preview is not uploaded to
  App Store Connect.

After approval, use the square master as the source for Icon Composer or the
Xcode asset catalog.
