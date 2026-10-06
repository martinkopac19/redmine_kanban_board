# Changelog

## 0.1.0 — 2026-10-06

First version — replacement for "Kanban board (Free)" 2.2.0 from the old Redmine.

- Board per project (tab *Kanban* after *Issues*) and across all projects (top menu).
  Module `kanban` and permission `view_kanban` keep the old plugin's names, so the board
  shows up in the same 54 projects for the same roles without any setup.
- One column per status, only statuses the trackers in scope actually use (workflow).
  Closed statuses show only tasks changed in the last 30 days; at most 500 cards (newest
  changes first, then sorted by priority), with a notice when more match.
- Native issue filters and saved queries (`IssueQuery`, no session — the issue list
  filter is not affected). Link to the issue list with the same filters.
- Drag & drop = normal status change: workflow, required fields, history, notifications,
  other plugins' hooks. A refused move snaps back and shows the reason.
- Moving to *Blocked* asks for the reason in a dialog styled like the other Previo dialogs.
  The reason is optional: *Save* stores the text, *Cancel* moves the card to Blocked without
  a reason, the × / Esc aborts the move. Blocked cards show a lock, the reason and how many
  days the task has been blocked (from history).
- When a task leaves Blocked (board, issue form, REST API, bulk edit / context menu), the
  reason is cleared; the old value stays in the issue history.
- Custom field **Blocked** (string, all trackers, filter + issue list column). Migration 001
  creates it and copies the 87 reasons from the old `kanban_issues.block_reason`
  (the old table is left untouched as a backup).
- Previo theme look (CSS variables), dark mode, EN/CS/SK/HU/PL/RO.
- Test: `extra/selftest.rb` (non-admin Developer, rolled-back transaction).
