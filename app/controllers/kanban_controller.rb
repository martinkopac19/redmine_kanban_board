class KanbanController < ApplicationController
  menu_item :kanban

  before_action :find_optional_project, only: :index
  before_action :authorize_index, only: :index

  helper :queries
  include QueriesHelper
  helper :issues
  helper :kanban

  # Nástenka nad natívnym IssueQuery: filtre, uložené dotazy aj práva sú tie isté ako v zozname
  # úloh. Session dotazu zoznamu úloh ZÁMERNE nepoužívame (use_session=false), aby nástenka
  # nemenila filter v zozname a naopak.
  def index
    retrieve_query(IssueQuery, false)
    @query.group_by = nil

    cond = closed_window_condition
    cond = merge_conditions(cond, Project.allowed_to_condition(User.current, :view_kanban)) unless @project
    scope = @query.base_scope.where(cond)
    @total = scope.count
    @issues = @query.issues(conditions: cond, limit: RedmineKanbanBoard::CARD_LIMIT,
                            order: "#{Issue.table_name}.updated_on DESC",
                            include: [:assigned_to, :tracker, :priority, :fixed_version, :custom_values])
                    .sort_by { |i| [-(i.priority&.position || 0), -i.updated_on.to_i] }
    @blocked_status = RedmineKanbanBoard.blocked_status
    @blocked_field = RedmineKanbanBoard.blocked_field
    @blocked_since = RedmineKanbanBoard.blocked_since(@issues, @blocked_status)
    @statuses = board_statuses(@issues)
    @by_status = @issues.group_by(&:status_id)
    @saved_queries = IssueQuery.visible.where(project_id: [nil, @project&.id].uniq).sorted.to_a
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Presun karty = bežná zmena stavu úlohy. Workflow rieši `safe_attributes` (nepovolený stav
  # ticho ignoruje, preto ho kontrolujeme), uloženie ide rovnakou cestou ako formulár úlohy
  # vrátane hookov ostatných pluginov.
  def move
    issue = Issue.visible.find(params[:issue_id])
    return render_403 unless User.current.allowed_to?(:view_kanban, issue.project)

    status = IssueStatus.find(params[:status_id])
    field = RedmineKanbanBoard.blocked_field
    blocked = RedmineKanbanBoard.blocked_status

    journal = issue.init_journal(User.current)
    attrs = { 'status_id' => status.id.to_s }
    if field && params.key?(:blocked_reason) && issue.available_custom_fields.include?(field)
      attrs['custom_field_values'] = { field.id.to_s => params[:blocked_reason].to_s.squish }
    end
    issue.safe_attributes = attrs

    if issue.status_id != status.id
      return render json: { error: l(:text_kanban_not_allowed, status: status.name) }, status: 422
    end

    saved = false
    Issue.transaction do
      call_hook(:controller_issues_edit_before_save,
                { params: params, issue: issue, time_entry: nil, journal: journal })
      if issue.save
        call_hook(:controller_issues_edit_after_save,
                  { params: params, issue: issue, time_entry: nil, journal: journal })
        saved = true
      else
        raise ActiveRecord::Rollback
      end
    end
    return render json: { error: issue.errors.full_messages.join(', ') }, status: 422 unless saved

    issue.reload
    since = RedmineKanbanBoard.blocked_since([issue], blocked)
    render json: {
      html: render_to_string(partial: 'kanban/card', formats: [:html],
                             locals: { issue: issue, since: since[issue.id], blocked_status: blocked,
                                       blocked_field: field, global: params[:global] == '1' })
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: l(:notice_file_not_found) }, status: 404
  rescue ActiveRecord::StaleObjectError
    render json: { error: l(:notice_issue_update_conflict) }, status: 409
  end

  private

  def find_optional_project
    @project = Project.find(params[:project_id]) if params[:project_id].present?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_index
    @project ? authorize : authorize_global
  end

  # Uzavreté stavy len za posledných N dní — inak by nástenka ťahala tisíce starých úloh.
  def closed_window_condition
    ["#{IssueStatus.table_name}.is_closed = ? OR #{Issue.table_name}.updated_on >= ?",
     false, RedmineKanbanBoard::CLOSED_DAYS.days.ago]
  end

  def merge_conditions(a, b)
    a_sql = Issue.sanitize_sql_array(a)
    "(#{a_sql}) AND (#{b})"
  end

  # Stĺpce: stavy, ktoré pripúšťa filter stavu, a len tie, ktoré trackery v rozsahu nástenky
  # naozaj používajú (workflow) — inak by mal každý projekt stĺpce všetkých stavov firmy.
  def board_statuses(issues)
    all = IssueStatus.sorted.to_a
    f = @query.filters['status_id']
    vals = f ? Array(f[:values]).map(&:to_s) : []
    allowed =
      case f && f[:operator]
      when 'o' then all.reject(&:is_closed)
      when 'c' then all.select(&:is_closed)
      when '='  then all.select { |s| vals.include?(s.id.to_s) }
      when '!'  then all.reject { |s| vals.include?(s.id.to_s) }
      else all
      end

    tf = @query.filters['tracker_id']
    trackers = @project ? @project.rolled_up_trackers.to_a : Tracker.sorted.to_a
    if tf && tf[:operator] == '='
      trackers = trackers.select { |t| Array(tf[:values]).map(&:to_s).include?(t.id.to_s) }
    end
    used = WorkflowTransition.where(tracker_id: trackers.map(&:id))
                             .distinct.pluck(:old_status_id, :new_status_id).flatten
    used |= trackers.map(&:default_status_id)
    used |= issues.map(&:status_id)
    allowed.select { |s| used.include?(s.id) }
  end
end
