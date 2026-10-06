# Redmine Kanban Board (Previo) — nástenka: jeden stĺpec = jeden stav úlohy.
#
# Náhrada pluginu „Kanban board (Free)" 2.2.0 zo starého Redmine, ktorý sa do 6.1 nepreniesol.
# Modul (`kanban`) aj oprávnenie (`view_kanban`) majú ZÁMERNE rovnaké názvy ako starý plugin:
# modul je v DB zapnutý v 54 projektoch a roly oprávnenie majú, takže nástenka sa objaví
# tam, kde bola, bez prenastavovania.
#
# Dôvod blokovania je bežné vlastné pole úlohy „Blocked" (migrácia 001 ho založí a prenesie
# doň dôvody zo starej tabuľky `kanban_issues`, ktorá v DB ostáva nedotknutá ako záloha).
# Dôvod je nepovinný; keď úloha z Blocked odíde, vymaže sa (lib/redmine_kanban_board/hooks.rb).
# Bez patchov jadra: úlohy berie natívny IssueQuery (filtre aj uložené dotazy),
# presun karty ukladá úlohu bežnou cestou (workflow, povinné polia, história, notifikácie).

require_relative 'lib/redmine_kanban_board'
require_relative 'lib/redmine_kanban_board/hooks'

Redmine::Plugin.register :redmine_kanban_board do
  name 'Redmine Kanban Board (Previo)'
  author 'Martin Kopáč'
  description 'Kanban board: one column per issue status, native issue filters, drag & drop status change, blocked reason.'
  version '0.1.0'
  url 'https://github.com/martinkopac19/redmine_kanban_board'
  requires_redmine version_or_higher: '6.0'

  settings default: { 'blocked_field_id' => '', 'blocked_status_id' => '' }

  project_module :kanban do
    permission :view_kanban, { kanban: [:index, :move] }, read: true
  end

  menu :project_menu, :kanban, { controller: 'kanban', action: 'index' },
       caption: :label_kanban, after: :issues, param: :project_id

  menu :top_menu, :kanban, { controller: 'kanban', action: 'index' },
       caption: :label_kanban,
       if: proc { User.current.logged? && User.current.allowed_to?(:view_kanban, nil, global: true) }
end
