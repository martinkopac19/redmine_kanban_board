module RedmineKanbanBoard
  # Úloha odchádza z Blocked → dôvod blokovania sa vymaže (rozhodnutie Martina, 6. 10. 2026).
  # Pole „Blocked" tak v zozname úloh ukazuje len aktuálne zablokované úlohy; starý dôvod
  # ostáva v histórii úlohy (zmena poľa sa zapíše do toho istého záznamu ako zmena stavu).
  #
  # Natívne hooky jadra pokrývajú formulár úlohy aj REST API (`edit`), hromadnú úpravu
  # a kontextové menu v zozname (`bulk_edit`) a presun na nástenke (KanbanController ich volá).
  class Hooks < Redmine::Hook::ViewListener
    def controller_issues_edit_before_save(context = {})
      RedmineKanbanBoard.clear_reason_when_unblocked(context[:issue])
    end

    def controller_issues_bulk_edit_before_save(context = {})
      RedmineKanbanBoard.clear_reason_when_unblocked(context[:issue])
    end
  end
end
