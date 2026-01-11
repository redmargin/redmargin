# Test Log

## Latest Run
- Started: 2026-01-10 22:31:37
- Command: `swift test --filter "ProcessRunnerTests/testHandlesMultipleArguments"`
- Status: PASS

### AppShellTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownDocumentLoadsContent | PASS | 0.003s | 2026-01-10 22:21:22 |
| testMarkdownDocumentHandlesUTF8 | PASS | 0.003s | 2026-01-10 22:21:14 |
| testMarkdownDocumentHandlesEmptyFile | PASS | 0.002s | 2026-01-10 22:20:54 |
| testMarkdownDocumentHandlesLargeFile | PASS | 0.012s | 2026-01-10 22:21:05 |

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
| testLoadAdditionFixture | PASS | 0.001s | 2026-01-10 22:24:54 |
| testLoadDeletionFixture | PASS | 0.001s | 2026-01-10 22:25:13 |
| testLoadModificationFixture | PASS | 0.001s | 2026-01-10 22:25:33 |
| testLoadMultipleHunksFixture | PASS | 0.001s | 2026-01-10 22:25:42 |
| testLoadEmptyFixture | PASS | 0.001s | 2026-01-10 22:25:24 |
| testLoadBinaryFixture | PASS | 0.001s | 2026-01-10 22:25:03 |
| testParseDiffOutputAddition | PASS | 0.002s | 2026-01-10 22:25:52 |
| testParseDiffOutputDeletion | PASS | 0.004s | 2026-01-10 22:26:12 |
| testParseDiffOutputModification | PASS | 0.002s | 2026-01-10 22:26:32 |
| testParseDiffOutputMultipleHunks | PASS | 0.002s | 2026-01-10 22:26:42 |
| testParseDiffOutputEmpty | PASS | 0.001s | 2026-01-10 22:26:22 |
| testParseDiffOutputBinary | PASS | 0.001s | 2026-01-10 22:26:02 |
| testGitChangeResultEmpty | PASS | 0.000s | 2026-01-10 22:24:23 |
| testGitChangeResultUntracked | PASS | 0.001s | 2026-01-10 22:24:42 |
| testGitChangeResultUntrackedEmptyFile | PASS | 0.000s | 2026-01-10 22:24:42 |
| testGitChangeResultEncodesToJSON | PASS | 0.001s | 2026-01-10 22:24:33 |

### GitDiffParserIntegrationTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testAddedLines | PASS | 0.111s | 2026-01-10 22:22:06 |
| testModifiedLines | PASS | 0.129s | 2026-01-10 22:23:27 |
| testDeletedLines | PASS | 0.110s | 2026-01-10 22:22:25 |
| testMultipleHunks | PASS | 0.130s | 2026-01-10 22:23:38 |
| testCleanFile | PASS | 0.108s | 2026-01-10 22:22:16 |
| testUntrackedFile | PASS | 0.100s | 2026-01-10 22:24:12 |
| testMixedAddAndDelete | PASS | 0.130s | 2026-01-10 22:23:18 |
| testFileInSubdirectory | PASS | 0.103s | 2026-01-10 22:22:35 |
| testNewRepoNoCommits | PASS | 0.061s | 2026-01-10 22:23:53 |
| testStagedButNotCommitted | PASS | 0.124s | 2026-01-10 22:24:03 |

### GitRepoDetectorTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDetectsRepoRoot | PASS | 0.112s | 2026-01-10 22:26:55 |
| testDetectsRepoRootFromSubdirectory | PASS | 0.102s | 2026-01-10 22:27:05 |
| testHandlesMissingFile | PASS | 0.014s | 2026-01-10 22:27:14 |
| testHandlesSubmodule | PASS | 0.382s | 2026-01-10 22:27:24 |
| testHandlesWorktree | PASS | 0.128s | 2026-01-10 22:27:34 |
| testPathContainsSpaces | PASS | 0.095s | 2026-01-10 22:27:43 |
| testPathContainsUnicode | PASS | 0.097s | 2026-01-10 22:27:53 |
| testReturnsNilForNonRepoFile | PASS | 0.015s | 2026-01-10 22:28:03 |

### GutterIntegrationTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testGitChangesForModifiedFile | PASS | 0.043s | 2026-01-10 22:29:18 |
| testGitChangeResultEncodesToCorrectFormat | PASS | 0.001s | 2026-01-10 22:29:47 |

### ProcessRunnerTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testRunsSimpleCommand | PASS | 0.007s | 2026-01-10 22:30:06 |
| testCapturesStderr | PASS | 0.007s | 2026-01-10 22:30:23 |
| testReturnsExitCode | PASS | 0.015s | 2026-01-10 22:30:42 |
| testHandlesWorkingDirectory | PASS | 0.007s | 2026-01-10 22:31:00 |
| testHandlesArgumentsWithSpaces | PASS | 0.005s | 2026-01-10 22:31:19 |
| testHandlesMultipleArguments | PASS | 0.006s | 2026-01-10 22:31:37 |

### FileWatcherTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDispatchSourceDetectsWrite | PASS | 0.003s | 2026-01-10 22:21:55 |
| testDispatchSourceDetectsMultipleWrites | PASS | 0.171s | 2026-01-10 22:21:47 |
| testDispatchSourceDetectsAtomicWrite | PASS | 0.004s | 2026-01-10 22:21:38 |
| testDispatchSourceAfterAtomicWriteNeedsRestart | PASS | 0.004s | 2026-01-10 22:21:30 |

## Notes
- 2026-01-10: Fixed testMixedAddAndDelete assertion - was incorrectly requiring modifiedRanges and rejecting deletedAnchors.
- 2026-01-10: Fixed testDispatchSourceDetectsMultipleWrites - changed to >= assertion (FS events can fire multiple times per write).
- 2026-01-10: Added GitDiffParserTests, GitDiffParserIntegrationTests, GitRepoDetectorTests, FileWatcherTests sections.
- 2026-01-10: Added testLineNumbersDefaultsToHidden to verify line numbers default to hidden for new files.
- 2026-01-10: Added MarkdownWebViewTests (2 tests) for Stage 2 WebView rendering: loads renderer.html, render() call succeeds with content verification.
- 2026-01-10: Tests use #file to locate WebRenderer from project source directory (not Bundle.main which points to Xcode during tests).
