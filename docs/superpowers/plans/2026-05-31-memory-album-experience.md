# Memory Album Experience Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current split photo carousel and narration page into a cover-led, elder-first audible life album with secondary timeline navigation and lightweight family contribution links.

**Architecture:** Keep the existing `MemoryAlbumRepository`, `MemoryAlbum`, and `NarrationPlayer` contracts. Change the cover selection order in the composer, then reshape `_MemoryBookView` into cover, reading, and timeline surfaces while reusing the existing narration panels and control bar. Route contribution prompts into the existing data pre-entry screen through `HomeScreen`.

**Tech Stack:** Flutter, Provider, existing local SQLite repository, `flutter_test`

---

### Task 1: Cover Photo Priority

**Files:**
- Modify: `test/memory_album_repository_test.dart`
- Modify: `lib/data/repositories/memory_album_repository.dart`

- [x] Add a repository test that composes an album with an avatar, a normal family photo, and a favorite memory photo, then expects the favorite memory photo to become `recommendedCoverPhotoId`.
- [x] Run `flutter test test/memory_album_repository_test.dart` and confirm the new test fails because the current implementation chooses the avatar.
- [x] Change `_pickCoverPhoto` to prefer favorite non-avatar images, then family images, then other non-avatar images, and finally avatars.
- [x] Run `flutter test test/memory_album_repository_test.dart` and confirm it passes.

### Task 2: Cover-Led Unified Reading Experience

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`

- [x] Replace the initial wall mode with a cover surface driven by `album.cover.recommendedCoverPhotoId`.
- [x] Add “开始听故事” and “先翻一翻” actions. The first enters the reading page and calls the existing `NarrationPlayer.play()`, while the second enters without autoplay.
- [x] Reuse the current narration list and bottom controls as the unified reading page.
- [x] Add a compact horizontal chapter strip and a reading header with a time-line action.
- [x] Reduce card stacking in chapter content by rendering album items as unframed story sections with photo-first hierarchy.

### Task 3: Timeline and Contribution Routing

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`

- [x] Add a secondary timeline surface using `album.timeline`.
- [x] Add lightweight contribution prompts in the reading page and timeline page.
- [x] Route contribution prompts to the existing data pre-entry screen.
- [x] Preserve the correct return target so data pre-entry returns to the memory album when opened from the album.

### Task 4: Verification

**Files:**
- Modify: `task_plan.md`
- Modify: `findings.md`
- Modify: `progress.md`

- [x] Run `flutter test`.
- [x] Run `dart analyze`.
- [x] Run `flutter build windows --debug`.
- [x] Run `flutter build web --debug`.
- [x] Start a local Web preview service and expose the actual Flutter build at `http://localhost:8092`.
- [x] Record verification evidence and any remaining risks in the planning documents.

### Task 5: Simplify Album Into Single Story Pages

**Files:**
- Create: `lib/core/memory_album/memory_album_story_pages.dart`
- Create: `test/memory_album_story_pages_test.dart`
- Modify: `lib/data/repositories/memory_album_repository.dart`

- [x] Add failing tests for fixed subtitle, story-only page selection, cover-photo fallback, and two-sentence body trimming.
- [x] Implement a small story-page mapper and fix album subtitle generation to `慢慢翻，也慢慢听`.
- [x] Run focused tests and confirm they pass.

### Task 6: Use Chat TTS For Current Story

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`

- [x] Replace the long narration page with a single-page album reader.
- [x] Use `VoiceOutputProvider.toggleReadAloud` for the current story only.
- [x] Stop playback when changing page, leaving the reader, or opening timeline.
- [x] Remove all contribution prompts from reader and timeline.
- [x] Keep the timeline as a secondary read-only entry.

### Task 7: Re-verify Simplified Album

**Files:**
- Modify: `findings.md`
- Modify: `progress.md`
- Modify: `task_plan.md`

- [x] Run Python TTS tests.
- [x] Run Flutter tests and static analysis.
- [x] Rebuild Windows and Web Debug artifacts.
- [x] Refresh the local Web preview and record verification evidence.
