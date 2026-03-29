# AGENTS.md — Marco Polo

## What This Is
A pure AppKit markdown editor for macOS. Lightweight, fast, distraction-free. For writing, not coding. Must feel instant on a 10-year-old Mac with a 50,000-line file open.

## Architecture (1924 lines total, 12 files)
- **AppDelegate.swift** — app lifecycle + full NSMenu (File, Edit, Format, View, Window)
- **Document.swift** — NSDocument, TextKit 2 stack, hosts sidebar + status bar, export, focus mode, preferences
- **EditorTextView.swift** — NSTextView subclass, typewriter scroll, auto-pair, smart newline, indent/outdent
- **FormattingCommands.swift** — extension on EditorTextView: toggle bold/italic/code/link, list continuation
- **MarkdownStyling.swift** — NSTextContentStorageDelegate, full syntax highlighting, focus mode dimming
- **MarkdownPatterns.swift** — static regex patterns, paragraph type detection, heading helpers
- **FencedCodeTracker.swift** — cross-paragraph fenced code block state tracking
- **OutlineSidebar.swift** — NSOutlineView heading tree, click-to-jump
- **StatusBarView.swift** — word/character count bar
- **MarkdownExporter.swift** — Markdown → HTML + PDF export
- **Preferences.swift** — UserDefaults wrapper (font, size, typewriter toggle)
- **main.swift** — entry point

Pure AppKit + **TextKit 2**. No SwiftUI. No Electron. No web views.

## MIGRATION: TextKit 1 → TextKit 2

The current code uses TextKit 1 (NSTextStorage + NSLayoutManager + NSTextContainer). **Migrate to TextKit 2** before adding any features. This is priority zero.

### Why
- TextKit 1 is deprecated. Apple is actively developing TextKit 2.
- TextKit 2 has lazy layout — only renders visible text. Massive RAM savings on large files.
- NSTextLayoutManager replaces NSLayoutManager with viewport-based rendering.
- NSTextContentStorage replaces NSTextStorage with better change tracking.

### How
- Replace `NSLayoutManager` → `NSTextLayoutManager`
- Replace `NSTextStorage` → `NSTextContentStorage`
- `MarkdownTextStorage` must be rewritten: instead of subclassing NSTextStorage, use `NSTextContentStorageDelegate` or `NSTextLayoutManagerDelegate` to apply styles
- `EditorTextView` stays as NSTextView subclass but configured for TextKit 2 (pass NSTextLayoutManager to init, NOT NSLayoutManager)
- Typewriter scroll logic in EditorTextView must be updated — glyph-based APIs (`glyphRange`, `boundingRect(forGlyphRange:)`) don't exist in TextKit 2. Use `NSTextLayoutManager.textLayoutFragment(for:)` and fragment frame geometry instead.
- Test: open a 50,000-line markdown file. It must scroll smoothly with <50MB RAM.

### Reference Projects (study these FIRST)

1. **STTextView** (PRIMARY) — https://github.com/krzyzanowskim/STTextView
   TextKit 2 text view built from scratch. Study their entire architecture: how they handle NSTextContentStorage, NSTextLayoutManager, viewport-based rendering, line fragment handling, gutter, and selection. This is the gold standard for TextKit 2 on macOS.

2. **SourceView** — https://github.com/ChimeHQ/SourceView
   NSTextView subclass on TextKit 2. Shows how to properly configure NSTextView in TextKit 2 mode and compose features. Closer to our approach (we subclass NSTextView, not build from scratch).

3. **MarkEdit** — https://github.com/MarkEdit-app/MarkEdit
   "TextEdit but for Markdown." Study their writing UX: keyboard shortcuts, find/replace, smart editing helpers.

4. **swift-markdown** — https://github.com/swiftlang/swift-markdown
   Apple's Markdown parser. Proper AST. Replace our hand-rolled `headingLevel(for:)` character loop with this.

## What Needs Work

### Syntax Highlighting (currently headings only)
Add styling for:
- **Bold** / *Italic* / ~~Strikethrough~~
- `Inline code`
- Block quotes (> prefix)
- Fenced code blocks (``` delimiters — style the whole block, no language-specific coloring needed)
- Lists (ordered + unordered, nested indentation)
- Links `[text](url)` — style the text portion, dim the URL
- Horizontal rules
- Task lists `- [ ]` / `- [x]`

All highlighting must be incremental — only re-style the edited paragraph, never the whole document.

### Writing Helpers
- Smart list continuation (Enter after `- item` → inserts `- `, Enter after `1. item` → inserts `2. `)
- Smart indent (Tab/Shift-Tab to indent/outdent list items and code blocks)
- Auto-pair: `**`, `` ` ``, `(`, `[`, `"` — wrap selected text when pair character is typed
- Toggle formatting shortcuts: Cmd+B bold, Cmd+I italic, Cmd+K link, Cmd+Shift+C code
- Smart quotes and dashes OFF by default (it's markdown, not Word)

### Navigation
- Outline sidebar (Cmd+Shift+O toggle) — heading tree, click to jump. Lightweight NSOutlineView, not a panel.
- Focus mode (Cmd+Shift+F) — dim all paragraphs except the one with the cursor. Just opacity on non-active paragraphs.
- Quick open (Cmd+P) — if multiple documents open, switch between them

### Editor Polish
- Word count + character count in a minimal status bar (bottom edge, tiny, optional Cmd+Shift+W toggle)
- Configurable font and font size (Cmd+Plus/Minus to resize, stored in UserDefaults)
- Remember window position and size between sessions
- Full-screen support (native macOS, no custom implementation)
- Export to HTML and PDF (Cmd+Shift+E menu)
- Proper menu bar (File, Edit, Format, View)

## Coding Rules

1. **Pure AppKit.** No SwiftUI, no web views, no Catalyst. System frameworks only.
2. **No third-party dependencies** unless critical. `swift-markdown` from Apple is acceptable. Nothing from CocoaPods/Carthage.
3. **RAM is precious.** TextKit 2's viewport-based layout is your friend — only styled/laid-out text is what's on screen. Never cache the full styled document. Profile with Instruments before and after any change.
4. **Viewport-driven.** Leverage NSTextLayoutManager's lazy layout. Only process visible text + a small buffer. Never iterate the full document on keystroke.
5. **NSDocument architecture.** All file I/O through the document model. Autosave in place.
6. **Typewriter scroll is sacred.** Cursor centering is a core feature. Toggleable via menu, on by default.
7. **Dark mode via semantic colors.** Use `.textColor`, `.textBackgroundColor`, `.secondaryLabelColor`, etc. Never hardcode RGB values. Light and dark mode work automatically.
8. **Keyboard-first.** Every action gets a shortcut. Mouse is secondary.
9. **One file, one concern.** Split at ~300 lines.
10. **No images, no themes, no line numbers.** This is a writing tool, not an IDE.

## Build & Run
- Xcode project: `MarcoPolo.xcodeproj`
- Target: macOS (AppKit)
- No package dependencies yet
- Open in Xcode → Cmd+R

## Priority Order
0. **Migrate to TextKit 2** (NSTextContentStorage + NSTextLayoutManager). Everything else builds on this.
1. Full markdown syntax highlighting (bold, italic, code, lists, quotes, links, tasks)
2. Writing helpers (smart lists, auto-pair, formatting shortcuts)
3. Focus mode
4. Outline sidebar
5. Word count status bar
6. Export (HTML, PDF)
7. Preferences (font, font size, typewriter toggle — UserDefaults, no window needed yet)

## Selection / Caret Notes

### Problem
- When line spacing is increased for a writing feel, AppKit can make the text, selection highlight, and caret feel bottom-anchored inside the taller line box. This makes the editor feel less balanced than iA Writer.

### Findings
- `lineHeightMultiple` inflates the line fragment, but the visual result can still feel bottom-heavy because selection and caret geometry are derived from TextKit segment and fragment metrics, not from any manual `baselineOffset` hack.
- The most robust open-source pattern is STTextView’s: do **not** push glyphs down with `.baselineOffset` attributes. Instead, keep paragraph geometry canonical, vend a custom `NSTextLayoutFragment`, and center each `NSTextLineFragment` during `draw(at:in:)` using its `typographicBounds` and the paragraph’s `lineHeightMultiple`.
- `NSTextLayoutManager.usesFontLeading` defaults to `YES`, and Apple explicitly notes that font leading is usually not appropriate for UI text. For editor-like text views, turning it off produces more settled line geometry.
- For insertion points, `NSTextLayoutManagerSegmentTypeStandard` is the better source than `.selection`, because `.standard` follows typographic bounds while `.selection` is shaped for range highlighting.
- If the default `NSTextView` selection still looks too tall or too low, the practical AppKit fix is to suppress the built-in selection fill with `selectedTextAttributes = [:]` and draw a custom selection background from TextKit segments in the text view background pass.
- STTextView’s selection highlight uses TextKit’s own `.selection` segment frames directly after the custom fragment renderer has centered the drawn lines. That is a stronger model than applying per-font optical offsets after layout.
- Final working selection rule in Marco Polo: use the raw `.selection` segment frames as-is. Do **not** round them with `.integral`, ceil/floor their height, or add optical padding. The overlap bug came from snapping `33.12pt` TextKit rows into `34pt` drawn rects, which forced adjacent rows to intersect by about 1 px.
- Keep the custom selection drawing visually dumb: plain rect fills, no rounded corners, no neighbor-merging logic, no per-font offsets. TextKit already provides the right geometry once line drawing is centered correctly.

### Caret Research Conclusion
- Stock `NSTextView` caret customization is good for width and color tweaks, but it is a weak foundation for a clearly short, blocky writing caret.
- The common public pattern is still `drawInsertionPoint(in:color:turnedOn:)` plus wider invalidation. Open examples from Christian Tietze and importRyan both follow that pattern; neither treats a truly short caret as a reliable stock-AppKit customization.
- TextKit 2 makes the stock insertion-point path less trustworthy. An Apple Developer Forums thread from April 2025 reports `shouldDrawInsertionPoint` firing while `drawInsertionPoint` is never called, yet the default blinking insertion point still appears.
- STTextView explicitly tracks this as `FB9713415` and avoids `NSTextView` baggage. CodeEditTextView follows the same high-level direction: custom editor rendering with an optional custom cursor view instead of leaning on the system caret.
- Marco Polo conclusion: for a visibly short, thick, style-driven caret, stop negotiating with the stock AppKit insertion point. Keep using TextKit 2 for geometry, but render our own caret.

### Plan: Render Our Own Caret
1. Create a tiny dedicated overlay view, preferably `EditorCaretView.swift`, whose only job is to draw and blink the caret. Keep selection drawing separate.
2. Make `EditorTextView` the geometry source. For a collapsed selection, resolve the caret anchor from TextKit 2 `.standard` segments, with a fragment-frame fallback for empty lines, trailing newlines, and viewport-edge cases.
3. Size the custom caret from optical design rules, not from font metrics. Start with a fixed block size that reads clearly, such as `14 x 10` or `14 x 12`, then center it vertically inside the source line box.
4. Hide the system insertion point defensively: set `insertionPointColor = .clear`, keep `drawInsertionPoint(in:color:turnedOn:)` as a no-op/clear path, and verify there is never a double caret.
5. Drive the overlay from local events only: selection changes, bounds/scroll changes, viewport layout updates, first-responder changes, window key-state changes, and font/typing-attribute changes.
6. Invalidate only the previous and new caret rects. Never trigger whole-document work and never iterate the full text on every blink.
7. Blink only when the editor is first responder, the window is key, and the selection is collapsed. Hide the custom caret immediately for range selections.
8. Keep the shape visually dumb: plain rect fill, no rounded corners, no adaptive per-font shaping. The selection fix already proved that simpler geometry is more robust across fonts.
9. Manual verification matrix: Lekton + IBM Plex Mono, start/middle/end of line, empty paragraph, trailing newline, long document, typewriter scroll on/off, light/dark mode.
10. If the system caret still leaks through under TextKit 2 after the overlay is in place, escalate to the stronger architecture used by STTextView and CodeEditTextView: full custom insertion-point ownership outside stock `NSTextView` drawing.

### References
- Apple Text Layout Programming Guide, line fragments vs used/typographic area:
  - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Concepts/CalcTextLayout.html
- Apple `NSTextLayoutManager` header docs, `usesFontLeading` and segment types:
  - https://developer.apple.com/documentation/appkit/nstextlayoutmanager
- STTextView insertion point handling:
  - https://github.com/krzyzanowskim/STTextView/blob/main/Sources/STTextViewAppKit/STTextView%2BInsertionPoint.swift
- STTextView selection rendering:
  - https://github.com/krzyzanowskim/STTextView/blob/main/Sources/STTextViewAppKit/STTextView.swift
- STTextView custom layout fragment centering:
  - https://github.com/krzyzanowskim/STTextView/blob/main/Sources/STTextViewAppKit/STTextLayoutFragment.swift
- STTextView custom layout fragment delegate hook:
  - https://github.com/krzyzanowskim/STTextView/blob/main/Sources/STTextViewAppKit/STTextView%2BNSTextLayoutManagerDelegate.swift
- STTextView repo and known TextKit 2 bug list:
  - https://github.com/krzyzanowskim/STTextView
- CodeEditTextView custom cursor architecture:
  - https://github.com/CodeEditApp/CodeEditTextView
- Christian Tietze on widening `NSTextView` caret:
  - https://christiantietze.de/posts/2017/08/nstextview-fat-caret/
- importRyan gist for wider `NSTextView` insertion point:
  - https://gist.github.com/importRyan/669999190f3b4db8e031c5971e7fa7ed
- Apple Developer Forums thread on TextKit 2 insertion-point override behavior:
  - https://developer.apple.com/forums/thread/779461?answerId=833303022
- TextKit 2 line-height experiment using fixed `minimumLineHeight` / `maximumLineHeight`:
  - https://gist.github.com/niw/f0eeea40468ab8c980f5b122d3a57ffd
- `usesFontLeading` explanation from a TextKit-focused deck:
  - https://speakerdeck.com/kishikawakatsumi/mastering-textkit
