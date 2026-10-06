module KanbanHelper
  def kanban_path_for(project, options = {})
    project ? project_kanban_path(project, options) : kanban_path(options)
  end

  def kanban_blocked_days(since)
    return nil unless since
    days = ((Time.current - since) / 1.day).floor
    l(:label_kanban_days, count: [days, 0].max)
  end
end
