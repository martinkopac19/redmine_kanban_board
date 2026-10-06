# Pole „Blocked" (dôvod blokovania) + prenos dôvodov zo starého pluginu Kanban board (Free).
#
# Starý plugin mal dôvod v tabuľke `kanban_issues.block_reason`. Tabuľka prešla migráciou
# do nového Redmine a ZOSTÁVA nedotknutá (záloha). Tu sa len skopírujú neprázdne dôvody
# do bežného vlastného poľa — vtedy ich vidno v detaile úlohy, dajú sa zobraziť ako stĺpec
# v zozname úloh a filtrovať.
#
# Idempotentné: pole sa hľadá podľa názvu, hodnota sa zapíše len tam, kde ešte žiadna nie je.
# Bez záznamu v histórii a bez notifikácií (priamy zápis custom_values).
class CreateBlockedField < ActiveRecord::Migration[6.1]
  NAME = 'Blocked'.freeze

  def up
    field = IssueCustomField.find_by(name: NAME)
    unless field
      field = IssueCustomField.new(
        name: NAME, field_format: 'string', max_length: 1000,
        description: 'Why the task is blocked (Kanban board asks for it when a card is moved to Blocked).',
        is_for_all: true, is_filter: true, searchable: true, visible: true, editable: true, is_required: false
      )
      field.tracker_ids = Tracker.pluck(:id)
      field.save!
    end

    copied = 0
    if table_exists?(:kanban_issues)
      rows = select_rows(<<~SQL)
        SELECT k.issue_id, k.block_reason FROM kanban_issues k
        JOIN issues i ON i.id = k.issue_id
        WHERE COALESCE(TRIM(k.block_reason), '') <> ''
      SQL
      rows.each do |issue_id, reason|
        cv = CustomValue.find_or_initialize_by(customized_type: 'Issue', customized_id: issue_id.to_i,
                                               custom_field_id: field.id)
        next if cv.value.present?

        cv.value = reason.to_s.squish
        cv.save!(validate: false)
        copied += 1
      end
    end

    status = IssueStatus.find_by(name: NAME)
    s = (Setting.plugin_redmine_kanban_board || {}).to_h.stringify_keys
    Setting.plugin_redmine_kanban_board = s.merge('blocked_field_id' => field.id.to_s,
                                                  'blocked_status_id' => status&.id.to_s)
    say "Blocked field ##{field.id}, copied #{copied} reasons from kanban_issues"
  end

  def down
    # Pole sa NEMAŽE — boli by preč aj dôvody zadané v novom Redmine. Pôvodné dáta
    # ostávajú v `kanban_issues`.
  end
end
