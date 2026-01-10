# Test Log

## Latest Run
- Started: 2026-01-10 17:04:21
- Ended: 2026-01-10 17:04:26
- Command: `xcodebuild test -scheme Redmargin -destination 'platform=macOS' -only-testing:RedmarginTests`
- Status: PASS
- Total tests: 7 Swift, 10 JavaScript

### AppShellTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownDocumentLoadsContent | PASS | 0.005s | 2026-01-10 17:04:24 |
| testMarkdownDocumentHandlesUTF8 | PASS | 0.003s | 2026-01-10 17:04:24 |
| testMarkdownDocumentHandlesEmptyFile | PASS | 0.003s | 2026-01-10 17:04:24 |
| testMarkdownDocumentHandlesLargeFile | PASS | 0.006s | 2026-01-10 17:04:24 |
| testLineNumbersDefaultsToHidden | PASS | 0.002s | 2026-01-10 17:04:24 |

### MarkdownWebViewTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testWebViewLoadsRendererHTML | PASS | 0.585s | 2026-01-10 16:59:38 |
| testRenderCallReturnsWithoutError | PASS | 2.015s | 2026-01-10 16:59:38 |

### JavaScript Tests (WebRenderer)
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownItRendersBasicMarkdown | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnHeading | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnParagraph | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnMultilineBlock | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnTable | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnListItems | PASS | - | 2026-01-10 16:59:38 |
| testGFMTableRenders | PASS | - | 2026-01-10 16:59:38 |
| testTaskListRenders | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnBlockquote | PASS | - | 2026-01-10 16:59:38 |
| testSourceposOnHorizontalRule | PASS | - | 2026-01-10 16:59:38 |

## Notes
- 2026-01-10: Added testLineNumbersDefaultsToHidden to verify line numbers default to hidden for new files.
- 2026-01-10: Added MarkdownWebViewTests (2 tests) for Stage 2 WebView rendering: loads renderer.html, render() call succeeds with content verification.
- 2026-01-10: Tests use #file to locate WebRenderer from project source directory (not Bundle.main which points to Xcode during tests).
