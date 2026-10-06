# Selftest Kanban nástenky (redmine_kanban_board).
# Beží proti živej DB, ale VŠETKO je vo vonkajšej transakcii, ktorá sa na konci zahodí.
# Maily nikam neodchádzajú (delivery_method :test). Testuje sa ako bežný človek (nie admin),
# s rolou Developer v projekte — práve tam rozhoduje workflow.
#
#   docker compose exec -T --user redmine redmine sh -c \
#     'SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE" bin/rails runner -e production plugins/redmine_kanban_board/extra/selftest.rb'

$ok = 0
$bad = 0
def check(name, actual, expected)
  if actual == expected
    $ok += 1; puts "  #{name.ljust(58)}: OK"
  else
    $bad += 1; puts "  #{name.ljust(58)}: CHYBA (ocakavane #{expected.inspect}, prislo #{actual.inspect})"
  end
end

puts '=' * 72
puts 'Selftest: Kanban nastenka'
puts '=' * 72

field = RedmineKanbanBoard.blocked_field
blocked = RedmineKanbanBoard.blocked_status
check('pole Blocked existuje', field&.name, 'Blocked')
check('stav Blocked najdeny', blocked&.name, 'Blocked')
check('pole je dostupne ako stlpec v zozname', IssueQuery.new.available_columns.any? { |c| c.name == :"cf_#{field.id}" }, true)
check('prenesene dovody (aspon 87)', CustomValue.where(custom_field_id: field.id).where.not(value: [nil, '']).count >= 87, true)

orig_method = ActionMailer::Base.delivery_method
ActionMailer::Base.delivery_method = :test
orig_forgery = ActionController::Base.allow_forgery_protection
ActionController::Base.allow_forgery_protection = false

conn = ActiveRecord::Base.connection
conn.begin_transaction(joinable: false)
begin
  # maily v tom istom vlákne — vlákna na pozadí by nevideli dáta z nepotvrdenej transakcie
  Mailer.with_synched_deliveries do
  # projekt s nástenkou a dosť úlohami, aby sa našla úloha s povoleným aj zakázaným prechodom
  project = Project.active.select { |p| p.module_enabled?(:kanban) }.max_by { |p| p.issues.open.count }
  role = Role.find_by(name: 'Developer')
  pw = 'Kanban-selftest-1!'
  u = User.new(firstname: 'Kanban', lastname: 'Selftest', mail: 'kanban-selftest@previo.info')
  u.login = 'kanban_selftest'; u.password = pw; u.password_confirmation = pw; u.status = User::STATUS_ACTIVE
  u.save!
  Member.create!(project: project, principal: u, role_ids: [role.id])

  s = ActionDispatch::Integration::Session.new(Rails.application)
  s.host! 'localhost'
  s.post '/login', params: { username: u.login, password: pw }
  check('prihlasenie testovacieho cloveka', s.response.status, 302)

  s.get "/projects/#{project.identifier}/kanban"
  check('nastenka v projekte sa zobrazi', s.response.status, 200)
  check('nastenka ma stlpec Blocked', s.response.body.include?('data-status-name="Blocked"'), true)

  issue = project.issues.joins(:status).where(issue_statuses: { is_closed: false }).order(:id).detect do |i|
    allowed = i.new_statuses_allowed_to(u)
    allowed.any? { |st| st.id != i.status_id && st.id != blocked.id } && IssueStatus.where.not(id: allowed.map(&:id)).exists?
  end
  allowed = issue.new_statuses_allowed_to(u)
  ok_status = allowed.detect { |st| st.id != issue.status_id && st.id != blocked.id }
  bad_status = IssueStatus.where.not(id: allowed.map(&:id)).first
  puts "  uloha ##{issue.id} (#{issue.status.name}), povolene: #{ok_status.name}, zakazane: #{bad_status.name}"

  puts "\n[1] presun, ktory workflow nedovoli"
  s.post '/kanban/move', params: { issue_id: issue.id, status_id: bad_status.id }, as: :json
  check('odmietnute (422)', s.response.status, 422)
  check('stav sa nezmenil', Issue.find(issue.id).status_id, issue.status_id)

  puts "\n[2] povoleny presun"
  n = issue.journals.count
  s.post '/kanban/move', params: { issue_id: issue.id, status_id: ok_status.id }, as: :json
  check('ulozene (200)', s.response.status, 200)
  check('stav je novy', Issue.find(issue.id).status_id, ok_status.id)
  check('v historii pribudol zaznam', Issue.find(issue.id).journals.count, n + 1)
  check('odpoved obsahuje kartu', JSON.parse(s.response.body)['html'].to_s.include?("data-issue-id=\"#{issue.id}\""), true)

  if Issue.find(issue.id).new_statuses_allowed_to(u).include?(blocked)
    back = Issue.find(issue.id).status
    puts "\n[3] do Blocked bez dovodu (dovod je nepovinny)"
    s.post '/kanban/move', params: { issue_id: issue.id, status_id: blocked.id, blocked_reason: '' }, as: :json
    check('ulozene (200)', s.response.status, 200)
    i = Issue.find(issue.id)
    check('stav Blocked, dovod prazdny', [i.status_id, i.custom_field_value(field).to_s], [blocked.id, ''])

    puts "\n[4] dovod doplneny (Blocked -> Blocked sa nedeje, ide cez dalsi presun)"
    s.post '/kanban/move', params: { issue_id: issue.id, status_id: back.id }, as: :json
    s.post '/kanban/move', params: { issue_id: issue.id, status_id: blocked.id, blocked_reason: '  cakame  na partnera ' }, as: :json
    check('ulozene (200)', s.response.status, 200)
    i = Issue.find(issue.id)
    check('stav Blocked a dovod ulozeny', [i.status_id, i.custom_field_value(field)], [blocked.id, 'cakame na partnera'])

    puts "\n[6] odchod z Blocked na nastenke maze dovod"
    if i.new_statuses_allowed_to(u).include?(back)
      n = i.journals.count
      s.post '/kanban/move', params: { issue_id: issue.id, status_id: back.id }, as: :json
      i = Issue.find(issue.id)
      check('stav zmeneny, dovod vymazany', [i.status_id, i.custom_field_value(field).to_s], [back.id, ''])
      d = i.journals.order(:id).last.details.detect { |x| x.property == 'cf' && x.prop_key == field.id.to_s }
      check('stary dovod je v historii', [i.journals.count, d&.old_value], [n + 1, 'cakame na partnera'])

      puts "\n[7] odchod z Blocked cez formular ulohy maze dovod"
      s.post '/kanban/move', params: { issue_id: issue.id, status_id: blocked.id, blocked_reason: 'druhy dovod' }, as: :json
      i = Issue.find(issue.id)
      s.patch "/issues/#{i.id}", params: { issue: { status_id: back.id, lock_version: i.lock_version } }
      check('formular ulozil (302)', s.response.status, 302)
      i = Issue.find(issue.id)
      check('stav zmeneny, dovod vymazany', [i.status_id, i.custom_field_value(field).to_s], [back.id, ''])
    else
      puts '  (Developer sa z Blocked nevie vratit — preskocene)'
    end
  else
    puts "\n[3-7] Developer nesmie z tohto stavu do Blocked — preskocene"
  end

  puts "\n[5] projekt bez modulu Kanban"
  other = Project.active.detect { |p| !p.module_enabled?(:kanban) && p.issues.exists? }
  if other
    Member.create!(project: other, principal: u, role_ids: [role.id])
    s.get "/projects/#{other.identifier}/kanban"
    check('nastenka nie je dostupna (403)', s.response.status, 403)
  else
    puts '  (vsetky projekty maju Kanban — preskocene)'
  end
  end
ensure
  conn.rollback_transaction
  ActionMailer::Base.delivery_method = orig_method
  ActionMailer::Base.deliveries.clear
  ActionController::Base.allow_forgery_protection = orig_forgery
end

puts "\n" + '=' * 72
puts "OK: #{$ok}   CHYBA: #{$bad}"
puts '(vsetky zmeny zahodene, v DB nezostalo nic, ziadny mail neodisiel)'
exit($bad.zero? ? 0 : 1)
