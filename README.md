# Markdown Editor

**Native macOS Markdown editing with live GitHub-styled preview, instant Quick Look inspection, and frictionless multi-format publishing.**

<p align="center">
  <img src="Resources/AppIcon.svg" width="128" height="128" alt="Markdown Editor Icon" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12.0%2B-black?logo=apple" alt="macOS 12.0+" />
  <img src="https://img.shields.io/badge/Swift-5.7-F05138?logo=swift&logoColor=white" alt="Swift 5.7" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%7C%20x86__64)-blue" alt="Universal Binary" />
  <img src="https://img.shields.io/badge/Tests-53%20passed-success" alt="Tests 53 passed" />
  <img src="https://img.shields.io/badge/License-GPL%20v2-green" alt="GPL v2" />
</p>

Markdown Editor delivers an authentic macOS desktop experience for technical authors, documentation writers, and developers. Built entirely in native Swift and AppKit without external dependencies or Electron bloat, it pairs a responsive plain-text Markdown editor with a synchronized, GitHub-styled live preview. Whether drafting technical specifications, inspecting files in Finder via spacebar Quick Look, copying formatted text directly into Google Docs or Mail, or converting documents from the command line, Markdown Editor provides a cohesive, reliable writing environment.

---

## Why Markdown Editor

Traditional Markdown tools often force a choice between heavyweight web wrappers that consume system resources and bare-bones text editors that lack immediate visual fidelity. 

Markdown Editor bridges this gap by combining native AppKit performance with production-grade document handling:

* **Instant Visual Alignment**: Write in raw Markdown on the left while watching the exact GitHub-rendered output update side by side, complete with synchronized scroll tracking and native light/dark appearance matching.
* **Frictionless Cross-App Sharing**: Copy documents as formatted rich text with a single shortcut (⌥⇧⌘C) and paste cleanly into Google Docs, Microsoft Word, Apple Pages, or Mail—no manual conversion or styling adjustments required.
* **Deep macOS Integration**: Preview Markdown files directly in Finder by pressing Spacebar via the bundled Quick Look extension, and tile windows effortlessly with yabai or Amethyst thanks to an in-window tab architecture.
* **Publish Anywhere**: Export to HTML, vector PDF, Word (DOCX), OpenDocument (ODT), and RTF through native sheet dialogs or headlessly via the built-in CLI for automated workflows.
* **Security by Design**: Protect against malicious content with an allow-list HTML sanitizer, sandboxed Quick Look previews with zero network access, and strict link execution policies that keep local scripts and executables from running automatically.

---

## Key Capabilities

### Synchronized Split-Pane Workspace
* **Real-Time Preview Updates**: Edits update the preview progressively without jumping or flickering, updating only altered fragments in the DOM.
* **Proportional Scroll Lock**: The preview automatically tracks the editor viewport so reference text and rendered output stay aligned.
* **Flexible Pane Layouts**: Drag the divider to your preferred split ratio (persisted automatically), or toggle the editor (⌃⌘E) or preview (⌃⌘P) to work in a dedicated distraction-free view.

### High-Fidelity GitHub Flavored Markdown (GFM)
* **Zero-Dependency Native Parser**: Complete built-in support for ATX/setext headings, tables with column alignments, task lists, nested bullet/ordered lists, blockquotes, GitHub alerts (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`), footnotes, autolinks, and fenced code blocks.
* **Adaptive Light & Dark Themes**: The preview faithfully reproduces GitHub's default and dark themes, following your macOS system appearance or toggling manually to System, Light, or Dark modes.

### Universal Multi-Format Export & Headless CLI
* **Versatile Document Formats**: Generate standalone HTML documents, paginated PDFs with printable margins, Word (DOCX), OpenDocument (ODT), or Rich Text (RTF).
* **Automated Batch Processing**: Convert documents in shell scripts, build jobs, or terminal workflows using the native headless export flag:
  ```bash
  "build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export spec.md spec.pdf
  ```

### One-Click Clipboard Conversion
* **Copy Rich Text (⌥⇧⌘C)**: Copies rendered styling to the system clipboard, ready to paste into formatted word processors and web apps.
* **Copy HTML (⌥⌘C) & Markdown (⇧⌘C)**: Instantly access raw HTML markup or source Markdown from the format bar or menu shortcuts.
* **Preview Text Selection**: Highlight any rendered text in the preview and press ⌘C to copy it immediately as formatted rich text.

### Zero-Click Finder Quick Look Extension
* **Spacebar Previews**: Press Spacebar on any `.md`, `.markdown`, or `.mkd` file in macOS Finder to display an authentic GitHub-rendered preview without launching an application.
* **Safe Sandbox**: Operates under a strict Content Security Policy with zero remote resource downloads and disabled script execution. Files over 10 MB are gracefully capped to preserve system memory.

### Thoughtful, Native Writing Ergonomics
* **Google Docs Shortcut Compatibility**: Familiar formatting shortcuts (⌘B, ⌘I, ⌥⌘1–6 for headings, ⌥⌘0 for normal text, ⇧⌘7/8/9 for lists) make formatting intuitive.
* **Intelligent Typing Behaviors**: Pressing Return continues ordered lists, bullet lists, task checkboxes, and blockquotes automatically; pressing Return on an empty list item terminates the list. Tab and ⇧Tab adjust indentation.
* **Vim-Style Gutter Line Numbers**: Optional dimmed line numbers scale efficiently across large files without slowing down typing.
* **Accidental Quit Protection (QuitGuard)**: Pressing ⌘Q displays a transient floating prompt; a deliberate second press within 1.5 seconds is required to exit.
* **Focus Autosave**: Automatically writes pending changes in place when switching to another application or window.
* **Encoding Integrity**: Detects legacy character encodings (e.g., Windows Latin 1, Shift-JIS, UTF-16), preserves Byte Order Marks (BOM), and alerts you if newly typed characters require saving as UTF-8.

---

## Product Experience

```text
1. Open or Inspect  ───>  Press Space in Finder for instant Quick Look, or open documents in tabs.
2. Draft & Format   ───>  Write Markdown with Docs-compatible shortcuts or the adaptive format bar.
3. Review Live      ───>  Monitor synchronized GitHub styling across adaptive Light/Dark modes.
4. Share & Publish  ───>  Copy formatted rich text to email or export to PDF/DOCX/HTML via GUI or CLI.
```

---

## What Makes It Different

| Capability | Markdown Editor | Electron / Web-Based Editors | Standard Text Editors |
|---|---|---|---|
| **Architecture** | Native Swift & AppKit (Universal) | Chromium + Node.js runtime | Native AppKit / Cocoa |
| **Startup & Footprint** | Instant launch, zero runtime overhead | High memory usage, background processes | Instant launch, minimal memory |
| **Preview Fidelity** | Native GitHub Flavored Markdown engine | Web preview or Markdown preview | Plain text only |
| **Quick Look Extension** | Bundled native `.appex` extension | Not included or separate utility | Raw unformatted text only |
| **Window Management** | In-window tabs (1 window per tab group) | Spawns multiple windows or OS tabs | Multi-window or standard OS tabs |
| **Tiling Manager Friendly** | Fully compatible with yabai & Amethyst | Inconsistent frame and tab behavior | Window-per-document model |
| **Clipboard Rich Text** | Clean paste into Docs, Word, Mail | Inconsistent styling copy | Raw Markdown text only |
| **Headless CLI Export** | Built-in `--export` CLI flag | Requires heavy headless browsers | External pandoc pipeline needed |
| **External Dependencies** | Zero external packages or frameworks | Hundreds of npm dependencies | Zero dependencies |

---

## Keyboard Shortcuts

### Formatting Shortcuts (Google Docs Compatible)

| Action | Shortcut | Action | Shortcut |
|---|---|---|---|
| **Bold** | `⌘B` | **Heading 1 – 6** | `⌥⌘1` … `⌥⌘6` |
| **Italic** | `⌘I` | **Normal Text** | `⌥⌘0` |
| **Underline** | `⌘U` | **Numbered List** | `⇧⌘7` |
| **Strikethrough** | `⇧⌘X` | **Bulleted List** | `⇧⌘8` |
| **Inline Code** | `⌘E` | **Checklist (Task List)** | `⇧⌘9` |
| **Code Block** | `⌥⌘K` | **Blockquote** | `⇧⌘B` |
| **Insert Link** | `⌘K` | **Indent / Outdent** | `⌘]` / `⌘[` *(or Tab / ⇧Tab)* |
| **Insert Image** | `⇧⌘I` | **Superscript / Subscript** | `⌘.` / `⌘,` |
| **Insert Table** | `⌥⇧⌘T` | **Horizontal Rule** | `⌥⌘-` |
| **HTML Comment** | `⌥⌘M` | **Clear Formatting** | `⌘\` |

### Tabs, Panes, and Document Management

| Action | Shortcut | Action | Shortcut |
|---|---|---|---|
| **New Tab** | `⌘T` | **Select Tab 1 – 8** | `⌘1` … `⌘8` |
| **New Window** | `⌘N` | **Select Last Tab** | `⌘9` |
| **Close Tab** | `⌘W` | **Toggle Editor Pane** | `⌃⌘E` |
| **Close Window** | `⇧⌘W` | **Toggle Preview Pane** | `⌃⌘P` |
| **Next / Previous Tab** | `⌃Tab` / `⌃⇧Tab` | **Quit Application** | `⌘Q` *(twice within 1.5s)* |

### Copy & Export Shortcuts

| Action | Shortcut | Description |
|---|---|---|
| **Copy Rich Text** | `⌥⇧⌘C` | Copies formatted text to paste into Docs, Word, Pages, Mail |
| **Copy Markdown** | `⇧⌘C` | Copies entire document as plain Markdown source |
| **Copy HTML** | `⌥⌘C` | Copies rendered HTML fragment markup |
| **Export HTML** | `⌥⌘E` | Saves standalone HTML with embedded GitHub CSS |
| **Export PDF** | `⌥⌘P` | Prints / exports styled paginated PDF |
| **Export ODT** | `⌥⌘O` | Exports OpenDocument text document |
| **Print Document** | `⌘P` | Opens native macOS print dialog for rendered preview |

---

## Command-Line Interface

Markdown Editor includes a headless conversion engine accessible directly from your terminal:

```bash
# Export Markdown to PDF
"build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export document.md output.pdf

# Export Markdown to HTML, Word, ODT, or Rich Text
"build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export notes.md notes.html
"build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export report.md report.docx
"build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export draft.md draft.odt
"build/Markdown Editor.app/Contents/MacOS/MarkdownEditor" --export snippet.md snippet.rtf
```

---

## Quick Start

### Build and Run Locally

Ensure you have macOS 12.0 or newer and Xcode Command Line Tools installed (`xcode-select --install`).

```bash
# 1. Compile the native host application bundle
make build

# 2. Launch Markdown Editor
make run
```

### Associate Markdown Files in Finder

Set Markdown Editor as the default handler for `.md`, `.markdown`, `.mdown`, and `.mkd` files to open them on double-click and display native document icons:

```bash
make default-app
```

### Enable Quick Look Previews

The Quick Look extension (`MarkdownQuickLook.appex`) is compiled and embedded inside the application bundle automatically. If pressing Space on a Markdown file does not display the rendered preview:

1. Launch `build/Markdown Editor.app` once to register the extension with LaunchServices.
2. In macOS **System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look**, ensure **Markdown Editor Quick Look** is enabled.
3. Reset macOS Quick Look server caches:
   ```bash
   qlmanage -r && qlmanage -r cache
   ```

---

## Build Targets & Development

The project provides a streamlined `Makefile` for compilation, packaging, and testing:

| Target | Command | Description |
|---|---|---|
| **Build Release** | `make build` | Compiles optimized host-native `.app` bundle into `build/` |
| **Build Debug** | `make build-debug` | Compiles with debug symbols and fast `-Onone` optimization |
| **Universal Build** | `make build-universal` | Builds a universal fat binary (`arm64` Apple Silicon + `x86_64` Intel) |
| **Run** | `make run` | Terminates active instances, recompiles, and opens the application |
| **Package DMG** | `make dmg` | Packages the application inside a styled disk image with custom background |
| **Run Tests** | `make test` | Executes the 53 native Swift unit and security test suites |
| **Reset Caches** | `make revoke` | Resets TCC permissions and flushes LaunchServices & Quick Look caches |
| **Clean** | `make clean` | Removes build directories and temporary compilation artifacts |

---

## Configuration

### Project Settings (`scripts/config.sh`)

App metadata and bundle configuration can be managed interactively via `make setup` or by editing `scripts/config.sh`:

```bash
export APP_NAME="MarkdownEditor"
export APP_DISPLAY_NAME="Markdown Editor"
export BUNDLE_ID="com.markdown.ed"
export MIN_MACOS_VERSION="12.0"
export LS_UI_ELEMENT="false"
```

### In-App Preferences

Configured under **Markdown Editor ▸ Settings**:
* **Appearance**: Choose between **System** (follows macOS dynamic theme), **Light**, or **Dark**.
* **Show Line Numbers**: Enables a dimmed, monospaced gutter ruler.
* **Save on Focus Loss**: Automatically commits changes when clicking outside the window or switching applications.

---

## Testing & Quality Assurance

The codebase includes an integrated native test suite covering Markdown rendering, formatting routines, edge cases, security invariants, and window state management:

```bash
make test
```

### Verified Test Coverage (53 Passing Tests)
* **Application Configuration & State**: Validates configuration, bundle versioning, menu uniqueness, format bar overflow handling, and `QuitGuard` timing.
* **Markdown Renderer Suite**: Tests ATX/setext headers with anchor slugs, nested ordered/unordered lists, task items, blockquotes, GitHub alerts, fenced code blocks with language specifiers, tables with escaped pipes, footnotes, and deep recursion bounds.
* **Formatter Suite**: Validates inline toggles (bold, italic, code), list continuation on Return, indent/outdent logic, link wrapping, and formatting stripping.
* **Security & Robustness Suite**: Enforces raw HTML allow-list filtering, link execution policy restrictions, linear rendering time on adversarial inputs, large document highlight scaling (300+ KB), and script blocking in print/PDF views.
* **Windows, Tabs & Panes**: Validates single-window in-app tab lifecycle, pane toggling, divider persistence, and focus autosave behavior.
* **Performance Behaviors**: Tests fragment-level DOM splicing (`PERF-002`), asynchronous preview rendering, scroll synchronization throttling, and progressive text highlighting on open.

---

## Automated Releases

Releases follow a deterministic 3-phase automated pipeline (**gather → ask → do**):

```bash
export GEMINI_API_KEY="your-api-key"
make release 1.0.0
```

1. **Gather**: Verifies clean working tree, validates version increment against git tags, runs the unit test suite, and drafts release notes summarizing commits.
2. **Ask**: Displays a full pre-flight confirmation including version bump, commit history, and release notes before taking action.
3. **Do**: Updates `VERSION`, compiles the universal binary, packages the styled distribution DMG, commits build counters, tags `vX.Y.Z`, and pushes to GitHub.

---

## License

This project is licensed under the **GNU General Public License v2.0** (GPL-2.0). See the [LICENSE](LICENSE) file for details.
