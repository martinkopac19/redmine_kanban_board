module RedmineKanbanBoard
  BLOCKED_NAME = 'Blocked'.freeze
  CARD_LIMIT = 500           # viac kariet nástenka neukáže (odkaz na zoznam úloh)
  CLOSED_DAYS = 30           # uzavreté stavy: len úlohy zmenené za posledných N dní

  module_function

  def settings
    Setting.plugin_redmine_kanban_board || {}
  end

  # Pole s dôvodom blokovania. Id z nastavení (založila ho migrácia), inak podľa názvu.
  def blocked_field
    id = settings['blocked_field_id'].to_i
    (id > 0 && IssueCustomField.find_by(id: id)) || IssueCustomField.find_by(name: BLOCKED_NAME)
  end

  def blocked_status
    id = settings['blocked_status_id'].to_i
    (id > 0 && IssueStatus.find_by(id: id)) || IssueStatus.find_by(name: BLOCKED_NAME)
  end

  def clear_reason_when_unblocked(issue)
    return unless issue.is_a?(Issue) && issue.status_id_changed?
    status = blocked_status
    field = blocked_field
    return unless status && field && issue.status_id_was == status.id && issue.status_id != status.id
    return if issue.custom_field_value(field).blank?

    issue.custom_field_values = { field.id.to_s => '' }
  end

  # Odkedy je úloha v stave Blocked: posledná zmena stavu na Blocked z histórie.
  # Jeden dotaz pre všetky karty. Úloha založená rovno v Blocked nemá záznam → created_on.
  def blocked_since(issues, status)
    return {} unless status
    ids = issues.select { |i| i.status_id == status.id }.map(&:id)
    return {} if ids.empty?

    since = JournalDetail.joins(:journal)
                         .where(property: 'attr', prop_key: 'status_id', value: status.id.to_s)
                         .where(journals: { journalized_type: 'Issue', journalized_id: ids })
                         .group('journals.journalized_id').maximum('journals.created_on')
    issues.each { |i| since[i.id] ||= i.created_on if ids.include?(i.id) }
    since
  end
end
