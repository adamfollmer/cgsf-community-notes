# frozen_string_literal: true

module ::CommunityNotes
  class Engine < ::Rails::Engine
    engine_name "community_notes"
    isolate_namespace CommunityNotes
  end
end
