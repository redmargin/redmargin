# Test Log

## Latest Run
- Started: 2026-01-13 12:27:30
- Command: Full test suite (91 Swift tests + 62 JS tests)
- Status: ALL PASS

### AppShellTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownDocumentLoadsContent | PASS | 0.005s | 2026-01-13 12:20:56 |
| testMarkdownDocumentHandlesUTF8 | PASS | 0.004s | 2026-01-13 12:21:14 |
| testMarkdownDocumentHandlesEmptyFile | PASS | 0.003s | 2026-01-13 12:21:25 |
| testMarkdownDocumentHandlesLargeFile | PASS | 0.012s | 2026-01-13 12:21:36 |

### BookmarkManagerTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testCreatesBookmark | PASS | 0.007s | 2026-01-13 12:21:58 |
| testResolvesBookmark | PASS | 0.006s | 2026-01-13 12:22:12 |
| testHandlesStaleBookmark | PASS | 0.009s | 2026-01-13 12:22:24 |
| testRemoveBookmark | PASS | 0.006s | 2026-01-13 12:22:32 |
| testCleanupStaleBookmarks | PASS | 0.005s | 2026-01-13 12:22:40 |
| testStartAccessingResource | PASS | 0.009s | 2026-01-13 12:22:47 |
| testStopAccessingAll | PASS | 0.009s | 2026-01-13 12:22:54 |

### FindTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testFindHighlightsMatches | PASS | 2.293s | 2026-01-13 12:23:46 |
| testFindNoMatches | PASS | 2.316s | 2026-01-13 12:23:51 |
| testFindNextCyclesToFirst | PASS | 2.209s | 2026-01-13 12:23:56 |
| testFindPreviousFromFirst | PASS | 2.320s | 2026-01-13 12:24:01 |
| testClearFindRemovesHighlights | PASS | 2.416s | 2026-01-13 12:24:06 |

### MarkdownWebViewTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testWebViewLoadsRendererHTML | PASS | 0.501s | 2026-01-13 12:26:40 |
| testRenderCallReturnsWithoutError | PASS | 2.084s | 2026-01-13 12:26:39 |

### JavaScript Tests (WebRenderer)
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testMarkdownItRendersBasicMarkdown | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnHeading | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnParagraph | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnMultipleBlock | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnTable | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnListItems | PASS | - | 2026-01-13 12:27:30 |
| testGFMTableRenders | PASS | - | 2026-01-13 12:27:30 |
| testTaskListRenders | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnBlockquote | PASS | - | 2026-01-13 12:27:30 |
| testSourceposOnHorizontalRule | PASS | - | 2026-01-13 12:27:30 |
| Sanitizer tests (46 tests) | PASS | - | 2026-01-13 12:27:30 |

### GitDiffParserTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testParseSimpleHunk | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseHunkOmittedOldCount | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseHunkOmittedNewCount | PASS | 0.000s | 2026-01-13 12:25:15 |
| testParseHunkBothOmitted | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseHunkAtStart | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseInvalidHunk | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseHunkWithTrailingContext | PASS | 0.011s | 2026-01-13 12:25:15 |
| testParseHunkPureDeletion | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadAdditionFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadDeletionFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadModificationFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadMultipleHunksFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadEmptyFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testLoadBinaryFixture | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseDiffOutputAddition | PASS | 0.002s | 2026-01-13 12:25:15 |
| testParseDiffOutputDeletion | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseDiffOutputModification | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseDiffOutputMultipleHunks | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseDiffOutputEmpty | PASS | 0.001s | 2026-01-13 12:25:15 |
| testParseDiffOutputBinary | PASS | 0.001s | 2026-01-13 12:25:15 |
| testGitChangeResultEmpty | PASS | 0.001s | 2026-01-13 12:25:15 |
| testGitChangeResultUntracked | PASS | 0.001s | 2026-01-13 12:25:15 |
| testGitChangeResultUntrackedEmptyFile | PASS | 0.001s | 2026-01-13 12:25:15 |
| testGitChangeResultEncodesToJSON | PASS | 0.001s | 2026-01-13 12:25:15 |

### GitDiffParserIntegrationTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testAddedLines | PASS | 0.164s | 2026-01-13 12:24:28 |
| testModifiedLines | PASS | 0.125s | 2026-01-13 12:24:31 |
| testDeletedLines | PASS | 0.154s | 2026-01-13 12:24:34 |
| testMultipleHunks | PASS | 0.118s | 2026-01-13 12:24:36 |
| testCleanFile | PASS | 0.124s | 2026-01-13 12:24:39 |
| testUntrackedFile | PASS | 0.127s | 2026-01-13 12:24:42 |
| testMixedAddAndDelete | PASS | 0.120s | 2026-01-13 12:24:45 |
| testFileInSubdirectory | PASS | 0.136s | 2026-01-13 12:24:47 |
| testNewRepoNoCommits | PASS | 0.067s | 2026-01-13 12:24:50 |
| testStagedButNotCommitted | PASS | 0.129s | 2026-01-13 12:24:53 |

### GitRepoDetectorTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDetectsRepoRoot | PASS | 0.101s | 2026-01-13 12:25:43 |
| testDetectsRepoRootFromSubdirectory | PASS | 0.099s | 2026-01-13 12:25:43 |
| testHandlesMissingFile | PASS | 0.014s | 2026-01-13 12:25:43 |
| testHandlesSubmodule | PASS | 0.353s | 2026-01-13 12:25:43 |
| testHandlesWorktree | PASS | 0.132s | 2026-01-13 12:25:43 |
| testPathContainsSpaces | PASS | 0.096s | 2026-01-13 12:25:43 |
| testPathContainsUnicode | PASS | 0.098s | 2026-01-13 12:25:43 |
| testReturnsNilForNonRepoFile | PASS | 0.014s | 2026-01-13 12:25:43 |

### GitStateWatcherTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testParseHEADForBranchRef | PASS | 0.004s | 2026-01-13 12:26:07 |
| testDetachedHEADHasNoRefPrefix | PASS | 0.005s | 2026-01-13 12:26:07 |
| testWatcherDetectsHEADChange | PASS | 0.007s | 2026-01-13 12:26:07 |
| testWatcherDetectsBranchRefChange | PASS | 0.006s | 2026-01-13 12:26:07 |
| testWatcherDetectsIndexChange | PASS | 0.007s | 2026-01-13 12:26:07 |

### GutterIntegrationTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testGitChangesForModifiedFile | PASS | 0.035s | 2026-01-13 12:26:21 |
| testGitChangeResultEncodesToCorrectFormat | PASS | 0.002s | 2026-01-13 12:26:21 |
| testGutterAppearsForChangedFile | PASS | 0.132s | 2026-01-13 12:26:21 |
| testGutterEmptyForCleanFile | PASS | 0.122s | 2026-01-13 12:26:21 |
| testGutterEmptyForNonRepoFile | PASS | 0.014s | 2026-01-13 12:26:21 |

### PreferencesManagerTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDefaultValues | PASS | 0.001s | 2026-01-13 12:26:53 |
| testThemePersists | PASS | 0.001s | 2026-01-13 12:26:53 |
| testInlineCodeColorPersists | PASS | 0.001s | 2026-01-13 12:26:53 |
| testGutterPreferencePersists | PASS | 0.002s | 2026-01-13 12:26:53 |
| testRemoteImagesPersists | PASS | 0.001s | 2026-01-13 12:26:53 |

### PrintTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testPrintConfigurationDefaults | PASS | 0.008s | 2026-01-13 12:27:10 |
| testPrintConfigurationCustomValues | PASS | 0.004s | 2026-01-13 12:27:10 |
| testPreparePrintAddsLightThemeClass | PASS | 1.998s | 2026-01-13 12:27:07 |
| testPreparePrintHidesGutterWhenConfigured | PASS | 0.507s | 2026-01-13 12:27:08 |
| testPreparePrintHidesLineNumbersWhenConfigured | PASS | 0.559s | 2026-01-13 12:27:09 |
| testRestoreFromPrintRemovesClasses | PASS | 0.877s | 2026-01-13 12:27:10 |

### ProcessRunnerTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testRunsSimpleCommand | PASS | 0.005s | 2026-01-13 12:27:23 |
| testCapturesStderr | PASS | 0.009s | 2026-01-13 12:27:23 |
| testReturnsExitCode | PASS | 0.007s | 2026-01-13 12:27:23 |
| testHandlesWorkingDirectory | PASS | 0.008s | 2026-01-13 12:27:23 |
| testHandlesArgumentsWithSpaces | PASS | 0.005s | 2026-01-13 12:27:23 |
| testHandlesMultipleArguments | PASS | 0.005s | 2026-01-13 12:27:23 |

### FileWatcherTests
| Test | Status | Duration | Last Run |
| --- | --- | --- | --- |
| testDispatchSourceDetectsWrite | PASS | 0.005s | 2026-01-13 12:23:15 |
| testDispatchSourceDetectsMultipleWrites | PASS | 0.167s | 2026-01-13 12:23:18 |
| testDispatchSourceDetectsAtomicWrite | PASS | 0.005s | 2026-01-13 12:23:20 |
| testDispatchSourceAfterAtomicWriteNeedsRestart | PASS | 0.011s | 2026-01-13 12:23:23 |

## Notes
- 2026-01-13: Added BookmarkManagerTests, FindTests, GitStateWatcherTests, PreferencesManagerTests, PrintTests sections.
- 2026-01-13: Updated sanitizer tests to 46 tests with new URL scheme allowlist tests.
- 2026-01-10: Fixed testMixedAddAndDelete assertion - was incorrectly requiring modifiedRanges and rejecting deletedAnchors.
- 2026-01-10: Fixed testDispatchSourceDetectsMultipleWrites - changed to >= assertion (FS events can fire multiple times per write).
- 2026-01-10: Added GitDiffParserTests, GitDiffParserIntegrationTests, GitRepoDetectorTests, FileWatcherTests sections.
- 2026-01-10: Added testLineNumbersDefaultsToHidden to verify line numbers default to hidden for new files.
- 2026-01-10: Added MarkdownWebViewTests (2 tests) for Stage 2 WebView rendering: loads renderer.html, render() call succeeds with content verification.
- 2026-01-10: Tests use #file to locate WebRenderer from project source directory (not Bundle.main which points to Xcode during tests).
