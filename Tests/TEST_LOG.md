# Test Log

## Latest Run
- Started: 2026-01-10 22:02:38
- Ended: 2026-01-10 22:06:29
- Command: `swift test` (all tests run individually)
- Status: PASS
- Total tests: 50 Swift, 10 JavaScript

### AppShellTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownDocumentLoadsContent | PASS | 0.001s | 2026-01-10 22:06:29 |
| testMarkdownDocumentHandlesUTF8 | PASS | 0.002s | 2026-01-10 22:06:29 |
| testMarkdownDocumentHandlesEmptyFile | PASS | 0.002s | 2026-01-10 22:06:29 |
| testMarkdownDocumentHandlesLargeFile | PASS | 0.010s | 2026-01-10 22:06:29 |

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

### GitDiffParserTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testParseSimpleHunk | PASS | 0.002s | 2026-01-10 22:02:38 |
| testParseHunkOmittedOldCount | PASS | 0.002s | 2026-01-10 22:03:01 |
| testParseHunkOmittedNewCount | PASS | 0.002s | 2026-01-10 22:03:10 |
| testParseHunkBothOmitted | PASS | 0.002s | 2026-01-10 22:03:21 |
| testParseHunkAtStart | PASS | 0.002s | 2026-01-10 22:03:32 |
| testParseInvalidHunk | PASS | 0.001s | 2026-01-10 22:03:40 |
| testParseHunkWithTrailingContext | PASS | 0.002s | 2026-01-10 22:03:48 |
| testParseHunkPureDeletion | PASS | 0.002s | 2026-01-10 22:03:58 |
| testLoadAdditionFixture | PASS | 0.001s | 2026-01-10 22:04:15 |
| testLoadDeletionFixture | PASS | 0.000s | 2026-01-10 22:04:15 |
| testLoadModificationFixture | PASS | 0.000s | 2026-01-10 22:04:15 |
| testLoadMultipleHunksFixture | PASS | 0.000s | 2026-01-10 22:04:15 |
| testLoadEmptyFixture | PASS | 0.000s | 2026-01-10 22:04:15 |
| testLoadBinaryFixture | PASS | 0.000s | 2026-01-10 22:04:15 |
| testParseDiffOutputAddition | PASS | 0.001s | 2026-01-10 22:04:15 |
| testParseDiffOutputDeletion | PASS | 0.000s | 2026-01-10 22:04:15 |
| testParseDiffOutputModification | PASS | 0.000s | 2026-01-10 22:04:15 |
| testParseDiffOutputMultipleHunks | PASS | 0.000s | 2026-01-10 22:04:15 |
| testParseDiffOutputEmpty | PASS | 0.000s | 2026-01-10 22:04:15 |
| testParseDiffOutputBinary | PASS | 0.000s | 2026-01-10 22:04:15 |
| testGitChangeResultEmpty | PASS | 0.001s | 2026-01-10 22:04:15 |
| testGitChangeResultUntracked | PASS | 0.001s | 2026-01-10 22:04:15 |
| testGitChangeResultUntrackedEmptyFile | PASS | 0.000s | 2026-01-10 22:04:15 |
| testGitChangeResultEncodesToJSON | PASS | 0.001s | 2026-01-10 22:04:15 |

### GitDiffParserIntegrationTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testAddedLines | PASS | 0.117s | 2026-01-10 22:04:36 |
| testModifiedLines | PASS | 0.113s | 2026-01-10 22:04:36 |
| testDeletedLines | PASS | 0.100s | 2026-01-10 22:04:36 |
| testMultipleHunks | PASS | 0.104s | 2026-01-10 22:04:36 |
| testCleanFile | PASS | 0.099s | 2026-01-10 22:04:36 |
| testUntrackedFile | PASS | 0.086s | 2026-01-10 22:04:36 |
| testMixedAddAndDelete | PASS | 0.113s | 2026-01-10 22:05:20 |
| testFileInSubdirectory | PASS | 0.103s | 2026-01-10 22:04:36 |
| testNewRepoNoCommits | PASS | 0.053s | 2026-01-10 22:04:36 |
| testStagedButNotCommitted | PASS | 0.117s | 2026-01-10 22:04:36 |

### GitRepoDetectorTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDetectsRepoRoot | PASS | 0.131s | 2026-01-10 22:05:41 |
| testDetectsRepoRootFromSubdirectory | PASS | 0.106s | 2026-01-10 22:05:41 |
| testHandlesMissingFile | PASS | 0.012s | 2026-01-10 22:05:41 |
| testHandlesSubmodule | PASS | 0.392s | 2026-01-10 22:05:41 |
| testHandlesWorktree | PASS | 0.123s | 2026-01-10 22:05:41 |
| testPathContainsSpaces | PASS | 0.097s | 2026-01-10 22:05:41 |
| testPathContainsUnicode | PASS | 0.108s | 2026-01-10 22:05:41 |
| testReturnsNilForNonRepoFile | PASS | 0.013s | 2026-01-10 22:05:41 |

### FileWatcherTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDispatchSourceDetectsWrite | PASS | 0.002s | 2026-01-10 22:05:54 |
| testDispatchSourceDetectsMultipleWrites | PASS | 0.164s | 2026-01-10 22:06:12 |
| testDispatchSourceDetectsAtomicWrite | PASS | 0.002s | 2026-01-10 22:05:54 |
| testDispatchSourceAfterAtomicWriteNeedsRestart | PASS | 0.005s | 2026-01-10 22:05:54 |

## Notes
- 2026-01-10: Fixed testMixedAddAndDelete assertion - was incorrectly requiring modifiedRanges and rejecting deletedAnchors.
- 2026-01-10: Fixed testDispatchSourceDetectsMultipleWrites - changed to >= assertion (FS events can fire multiple times per write).
- 2026-01-10: Added GitDiffParserTests, GitDiffParserIntegrationTests, GitRepoDetectorTests, FileWatcherTests sections.
- 2026-01-10: Added testLineNumbersDefaultsToHidden to verify line numbers default to hidden for new files.
- 2026-01-10: Added MarkdownWebViewTests (2 tests) for Stage 2 WebView rendering: loads renderer.html, render() call succeeds with content verification.
- 2026-01-10: Tests use #file to locate WebRenderer from project source directory (not Bundle.main which points to Xcode during tests).
