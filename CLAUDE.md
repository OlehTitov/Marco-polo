# CLAUDE.md — Marco Polo

## What This Is
A pure AppKit markdown editor for macOS. NSDocument-based, typewriter scrolling, live syntax highlighting. 288 lines of Swift across 5 files. The goal: a fast, beautiful, distraction-free writing tool.

## Architecture
- **MarkdownTextStorage** — NSTextStorage subclass, regex-free heading detection, paragraph-level styling
- **EditorTextView** — NSTextView subclass, typewriter scroll (cursor always centered)
- **Document** — NSDocument subclass, NSLayoutManager + NSTextContainer setup, autosave, plain text I/O
- **AppDelegate** — minimal, just app lifecycle
- **main.swift** — entry point

No SwiftUI. No Electron. No web views. Pure AppKit + TextKit 1.

## Reference Projects to Study

Clone these repos and study their patterns before making changes:

### 1. MarkEdit (primary reference — UX patterns)
- **Repo:** https://github.com/MarkEdit-app/MarkEdit
- **Why:** "TextEdit but for Markdown." Closest to what Marco Polo wants to be. Native Swift, polished UX.
- **Study:** Their toolbar, theme system, file handling, keyboard shortcuts, find/replace, and how they handle different markdown elements beyond headings.

### 2. STTextView (text engine upgrade path)
- **Repo:** https://github.com/krzyzanowskim/STTextView
- **Why:** Modern TextKit 2 replacement for NSTextView. Better performance, line numbers, plugin architecture for syntax highlighting.
- **Study:** How they handle line numbering, gutter rendering, selection highlighting, and their plugin system for extensible syntax styling.
- **Consider:** Replacing our raw NSTextView/NSTextStorage with STTextView as the text engine. This is the single biggest upgrade possible.

### 3. SourceView (TextKit 2 NSTextView patterns)
- **Repo:** https://github.com/ChimeHQ/SourceView
- **Why:** NSTextView subclass built on TextKit 2, from the Chime editor team. Shows how to properly subclass NSTextView with modern text architecture.
- **Study:** Their approach to TextKit 2 migration, text container handling, and how they compose features.

### 4. Inkdown (inline WYSIWYG rendering)
- **Repo:** https://github.com/seraphinerenard/inkdown
- **Why:** Typora-style live rendering — markdown syntax becomes styled text as you type.
- **Study:** How they render bold/italic/links/images inline without a separate preview pane.

### 5. swift-markdown (parser)
- **Repo:** https://github.com/swiftlang/swift-markdown
- **Why:** Apple's official Markdown parser. Proper AST instead of hand-rolled character scanning.
- **Consider:** Replace our `headingLevel(for:)` character loop with a real parser that handles the full Markdown spec.

## Current Limitations (What Needs Work)

### Syntax Highlighting
Currently only handles headings (H1-H6). Missing:
- **Bold** / *Italic* / ~~Strikethrough~~ / `inline code`
- Block quotes
- Code blocks (fenced + indented) with language-aware coloring
- Lists (ordered + unordered, nested)
- Links and images
- Horizontal rules
- Task lists (checkboxes)

### Editor Features Missing
- Line numbers in gutter
- Current line highlight
- Word count / character count (status bar)
- Multiple themes (light/dark at minimum, plus custom)
- Configurable font and font size
- Tab/indent behavior (2 vs 4 spaces, tab key inserts spaces)
- Auto-pair brackets, quotes, markdown markers (`**`, `` ` ``, etc.)
- Smart list continuation (press Enter after `- item` → inserts `- `)
- Command palette (Cmd+Shift+P)
- Outline/TOC sidebar (heading navigation)
- Focus mode (dim all paragraphs except current)
- Export to HTML / PDF
- Split view: editor + rendered preview (optional, toggle)

### Polish
- App icon
- Proper menu bar (Format menu, View menu with zoom/theme)
- Preferences window (font, theme, tab width, typewriter scroll toggle)
- Full-screen support
- Touch Bar support (if applicable)
- Remember window position and size

## Coding Rules

1. **Pure AppKit.** No SwiftUI wrappers, no web views, no Electron. If AppKit can do it natively, use AppKit.
2. **No third-party dependencies** unless absolutely necessary. Prefer system frameworks. Exception: `swift-markdown` from Apple is fine, and `STTextView` is acceptable as a text engine if migrating from TextKit 1.
3. **NSDocument architecture.** All file I/O goes through the document model. Don't bypass it.
4. **Performance matters.** This is a text editor — it must feel instant. Syntax highlighting must be incremental (only re-style changed paragraphs, not the whole document). Test with 10,000+ line files.
5. **Typewriter scroll is sacred.** The cursor-centering behavior in EditorTextView is a core feature. Any changes must preserve it. Make it toggleable but on by default.
6. **Dark mode support.** Use semantic colors (`.textColor`, `.textBackgroundColor`, etc.) — never hardcode colors. Test both modes.
7. **Keyboard-first.** Every action should have a keyboard shortcut. Mouse is secondary.
8. **One file, one concern.** Keep files focused. If a file grows past ~300 lines, split it.

## Build & Run
- Xcode project at `MarcoPolo.xcodeproj`
- Target: macOS (AppKit, no Catalyst)
- No package dependencies yet
- Open in Xcode → Cmd+R

## Priority Order
If improving Marco Polo, work in this order:
1. Full markdown syntax highlighting (bold, italic, code, lists, quotes, links)
2. Line numbers + current line highlight
3. Theme system (light/dark + 2-3 built-in themes)
4. Auto-pairing and smart list continuation
5. Word/character count status bar
6. Outline sidebar
7. Focus mode
8. Preview pane (split view, togglable)
9. Export (HTML, PDF)
10. Preferences window
