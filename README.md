# Epub-Reader


A native EPUB reader for iPhone and iPad, rebuilt from the ground up in Swift/UIKit. It parses EPUB 3 packages and renders them in a paginated `WKWebView` with highlighting, bookmarks, a table of contents, and rich theming.

## Screenshots

<table>
  <tr>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.18.png" alt="Paginated reading view" /><br/>
      <sub><b>Reading view</b><br/>Paginated, page-numbered text</sub>
    </td>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.22.png" alt="Glass command panel" /><br/>
      <sub><b>Command panel</b><br/>Quick actions & progress</sub>
    </td>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.27.png" alt="Table of contents" /><br/>
      <sub><b>Table of contents</b><br/>Chapters with page numbers</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.44.png" alt="Highlighted text" /><br/>
      <sub><b>Highlighting</b><br/>Color highlights in the text</sub>
    </td>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.41.png" alt="Highlights list" /><br/>
      <sub><b>Highlights list</b><br/>Every highlight in the book</sub>
    </td>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.55.12.png" alt="Bookmarks list" /><br/>
      <sub><b>Bookmarks</b><br/>Saved pages per book</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.49.png" alt="Themes and settings" /><br/>
      <sub><b>Themes &amp; settings</b><br/>Built-in themes & font size</sub>
    </td>
    <td align="center" width="33%">
      <img src="testReader/Screenshots/Simulator%20Screenshot%20-%20iPhone%2017%20-%202026-08-04%20at%2022.54.58.png" alt="Customize theme" /><br/>
      <sub><b>Customize theme</b><br/>Fonts, spacing & margins</sub>
    </td>
    <td align="center" width="33%"></td>
  </tr>
</table>

## Features

### Library
- Browse a list of available books with cover art and titles.
- Automatic discovery of EPUB files bundled in the app and dropped into the app's Documents directory (searched recursively).
- Tap any book to start reading.

### Reading experience
- EPUB 3 parsing of spine, metadata, cover image, and navigation document.
- Paginated rendering using CSS multi-column layout in `WKWebView` — no continuous scrolling.
- Turn pages by tapping the page edges or swiping; move between chapters seamlessly.
- Global page numbering ("current of total") and reading-progress percentage.
- Immersive mode: tap the center to hide/show the reading chrome.
- Floating menu button and a glass command panel for quick actions.
- Share the current book.
- Orientation lock toggle to pin the current orientation.

### Page transitions
Choose how pages animate:
- Slide
- Page curl
- Scroll

### Table of contents
- Chapter list with per-chapter page numbers, book cover, and overall progress.
- Tap a chapter to jump straight to it.

### Highlights
- Select text and highlight it in your choice of color (yellow, green, pink, blue, orange).
- Highlights are anchored to a stable character offset, so they survive re-pagination when you change font size, margins, or rotate the device.
- Highlights persist per book across app launches.
- A dedicated Highlights list shows every highlight in the book with its text and page number.
- Tap a highlight to navigate to the exact page where it appears (computed from the rendered layout, not a stale snapshot).
- Swipe to delete a highlight.

### Bookmarks
- One-tap bookmark for the current page; the floating menu icon animates to reflect the bookmarked state.
- Bookmarks are shown alongside highlights via a segmented control in the same list screen.
- Tap a bookmark to jump back to it; swipe to delete.
- Bookmarks persist per book.

### Themes & typography
- Six built-in themes — Original, Quiet, Paper, Bold, Calm, and Focus — each with tailored light and dark renditions.
- Appearance modes: Light, Dark, and Match Device.
- Increase or decrease font size on the fly.
- **Customize Theme** screen with a live, sticky preview:
  - Font family (Charter, Georgia, Times New Roman, Palatino, Helvetica, System)
  - Bold text
  - Line spacing
  - Character spacing
  - Word spacing
  - Margins
  - Justified text
  - Reset to defaults
- All theme and typography choices are remembered between sessions.

## Adding your own books
Drop an EPUB 3 file into the app's resources (or the on-device Documents directory) and it will be discovered, parsed, and listed in the library.

A good sample to test with:
`http://code.google.com/p/epub-revision/downloads/detail?name=9780316000000_MobyDick_r2.epub`

More about EPUB 3 features: http://idpf.org/epub/30

## Requirements
- Swift 5, UIKit (programmatic Auto Layout)
- Xcode with a recent iOS SDK
- iPhone and iPad supported

## Contributing
If you add enhancements to the existing code, please contribute those changes back here as well.

<!-- GitAds-Verify: LABL53P49GMGFW7QHJNUDWB2DK3EW7KZ -->

## GitAds Sponsored
[![Sponsored by GitAds](https://gitads.dev/v1/ad-serve?source=zerocoder1/epub-reader@github)](https://gitads.dev/v1/ad-track?source=zerocoder1/epub-reader@github)

