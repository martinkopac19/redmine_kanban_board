# Redmine Kanban Board

A lightweight Kanban board for Redmine: **one column per issue status**, drag a card to
change the status. It uses Redmine's own issue filters and saved queries, saves every move
through the normal issue update (workflow, required fields, history, notifications), and
adds an optional **Blocked** reason to issues.

Built for [Previo](https://previo.cz) as a replacement for a commercial Kanban plugin that
did not make it to Redmine 6, and released for the Redmine community.

## Features

- **Board per project** (a *Kanban* tab after *Issues*) and **across all projects**
  (top menu link).
- **One column per status**, limited to the statuses the trackers in scope actually use
  (workflow). Closed statuses show only issues changed in the last 30 days.
- **Native filters and saved queries** (`IssueQuery`). The board keeps its own filter and
  does not change the filter of the issue list. *View all issues* opens the list with the
  same filters.
- **Drag & drop = normal status change.** Workflow and required fields apply, the change is
  journaled and notified, and other plugins' `controller_issues_edit_*` hooks run. A move the
  workflow does not allow snaps back and shows the reason.
- **Blocked reason.** A custom field *Blocked* (string, filterable, available as an issue
  list column). Moving a card to the *Blocked* status opens a dialog: *Save* stores the
  reason, *Cancel* moves the card without a reason, × / Esc aborts the move. Blocked cards
  show a lock, the reason and how many days the issue has been blocked (from history).
  When an issue leaves *Blocked* — on the board, in the issue form, via REST API or bulk
  edit — the reason is cleared; the old value stays in the issue history.
- Cards show id, tracker, priority, subject, assignee (avatar) and target version, plus the
  project on the cross-project board. At most 500 cards (most recently updated first) with a
  notice when more issues match.
- Styled with CSS variables of the Previo themes (falls back to neutral colors elsewhere),
  dark mode support for `redmine_dark_mode`.
- Translations: English, Czech, Slovak, Hungarian, Polish, Romanian.

## Installation

```bash
cd $REDMINE_ROOT/plugins
git clone https://github.com/martinkopac19/redmine_kanban_board.git
bundle exec rake redmine:plugins:migrate NAME=redmine_kanban_board RAILS_ENV=production
# restart Redmine
```

Then enable the **Kanban** module in the project settings and give roles the
**View Kanban board** permission.

The migration creates the *Blocked* custom field (for all trackers) and remembers its id
and the id of the status named *Blocked* in the plugin settings. If a table
`kanban_issues` with a `block_reason` column exists (left over from the commercial
"Kanban board" plugin), non-empty reasons are copied into the new field; the old table is
left untouched.

Module (`kanban`) and permission (`view_kanban`) deliberately use the same names as that
plugin, so after a migration the board appears in the same projects for the same roles.

## Compatibility

- Tested on **Redmine 6.1.3** (Ruby 3.4, Rails 7.2, PostgreSQL).
- Declares `requires_redmine version_or_higher: '6.0'`.
- No core patches: a controller, views, two hooks and one data migration.

## Tests

`extra/selftest.rb` runs against a live database inside a transaction that is rolled back
(no mail is sent). It logs in as a temporary non-admin user with the *Developer* role and
checks the board, a move the workflow refuses, an allowed move, Blocked with and without
a reason, clearing the reason on the board and in the issue form, and access to a project
without the module.

```bash
bin/rails runner -e production plugins/redmine_kanban_board/extra/selftest.rb
```

## License

Copyright (C) 2026 Martin Kopáč

GPL-2.0-or-later, matching Redmine. See [LICENSE](LICENSE).

## Credits

Built for [Previo](https://previo.cz) and released for the Redmine community.
