# Cleanup Candidates

This document records files that were moved out of runtime paths or kept for a
later deletion decision. Nothing in this pass is permanently deleted.

## Archived In This Pass

Moved to `docs/archive/scaffold/`:

- `lib/data/models/_scaffold/`
- `lib/data/repositories/_scaffold/`
- `lib/logic/_scaffold/`

Reason: these files were documented as not connected to the UI/runtime path and
were also producing analyzer noise. They are now outside `lib/`, so Flutter will
not analyze or compile them.

Moved to `docs/archive/project-notes/`:

- `.temp_prompt.txt`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `data_preentry_todo.md`

Reason: these are planning/progress artifacts rather than runtime source files.

## Kept For Now

- `server/fixtures/`: referenced by `server/scripts/populate_tables.py`.
- `server/database.py`: referenced by server scripts and README, although not by
  `local_chat_server.py`.
- `docs/reference/vivo-asr-demos/`: reference material for vivo ASR behavior.
- `lib/data/repositories/asr_repository.dart`: compatibility export for the
  moved voice-input implementation.

## Deletion Requires Confirmation

After tests pass and the archive location is reviewed, the archived scaffold and
project-note files can be deleted only after an explicit confirmation.
