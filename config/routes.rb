RedmineApp::Application.routes.draw do
  get  'kanban',                   to: 'kanban#index', as: 'kanban'
  get  'projects/:project_id/kanban', to: 'kanban#index', as: 'project_kanban'
  post 'kanban/move',              to: 'kanban#move',  as: 'kanban_move'
end
