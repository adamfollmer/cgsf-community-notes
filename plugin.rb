# frozen_string_literal: true

# name: cgsf-community-notes
# about: Community notes — member-proposed context on posts, accepted by anonymous supermajority vote
# version: 0.1.0
# authors: Adam F.
# url: https://github.com/adamfollmer/cgsf-community-notes
# required_version: 2.7.0

enabled_site_setting :community_notes_enabled

register_asset "stylesheets/community-notes.scss"
register_svg_icon "note-sticky"

module ::CommunityNotes
  PLUGIN_NAME = "cgsf-community-notes"
  CATEGORIES = %w[correction conduct placement duplicate scam]
end

require_relative "lib/community_notes/engine"

after_initialize do
  class ::CommunityNotes::Note < ::ActiveRecord::Base
    self.table_name = "community_notes"

    belongs_to :post
    has_many :note_votes,
             class_name: "CommunityNotes::NoteVote",
             foreign_key: :note_id,
             dependent: :destroy

    validates :category, inclusion: { in: ::CommunityNotes::CATEGORIES }
    validate :word_limit

    # Membership count, not activity — lurkers count. Same principle as the
    # June design's percentage-thresholds-with-floors.
    def self.active_member_count
      User.real.where(active: true, staged: false).where(suspended_till: nil).count
    end

    def self.quorum
      floor = SiteSetting.community_notes_quorum_floor
      pct = SiteSetting.community_notes_quorum_percent / 100.0
      [floor, (pct * active_member_count).ceil].max
    end

    # Status is COMPUTED at read time — never stored — so threshold retunes
    # are retroactively safe. Acceptance "closes" voting via the controller
    # guard (no vote changes once accepted), which keeps this stable.
    def accepted?
      total = note_votes.count
      return false if total < self.class.quorum
      agrees = note_votes.where(agree: true).count
      (agrees.to_f / total) >= (SiteSetting.community_notes_agreement_percent / 100.0)
    end

    def agreement_percent
      total = note_votes.count
      return nil if total.zero?
      ((note_votes.where(agree: true).count.to_f / total) * 100).round
    end

    private

    def word_limit
      max = SiteSetting.community_notes_max_words
      if body.blank? || body.split.size > max
        errors.add(:body, I18n.t("community_notes.errors.word_limit", max: max))
      end
    end
  end

  class ::CommunityNotes::NoteVote < ::ActiveRecord::Base
    self.table_name = "community_note_votes"
    belongs_to :note, class_name: "CommunityNotes::Note"
  end

  class ::CommunityNotes::NotesController < ::ApplicationController
    requires_plugin ::CommunityNotes::PLUGIN_NAME
    before_action :ensure_logged_in

    def create
      post = Post.find(params.require(:post_id))
      raise Discourse::InvalidAccess if post.user_id == current_user.id # never on your own post
      if ::CommunityNotes::Note.exists?(post_id: post.id, author_id: current_user.id)
        return render_json_error(I18n.t("community_notes.errors.already_proposed"), status: 422)
      end

      note = ::CommunityNotes::Note.new(
        post_id: post.id,
        author_id: current_user.id,
        category: params.require(:category),
        body: params.require(:body),
      )
      if note.save
        render json: success_json.merge(note_id: note.id)
      else
        render_json_error(note.errors.full_messages.join(", "), status: 422)
      end
    end

    def vote
      note = ::CommunityNotes::Note.find(params[:id])
      raise Discourse::InvalidAccess if note.author_id == current_user.id # process owns the note, author abstains
      if note.accepted?
        return render_json_error(I18n.t("community_notes.errors.voting_closed"), status: 422)
      end

      agree = ActiveModel::Type::Boolean.new.cast(params.require(:agree))
      vote = ::CommunityNotes::NoteVote.find_or_initialize_by(note_id: note.id, user_id: current_user.id)
      vote.agree = agree
      vote.save!
      render json: success_json.merge(accepted: note.reload.accepted?)
    end
  end

  Discourse::Application.routes.append do
    post "/community-notes" => "community_notes/notes#create"
    put "/community-notes/:id/vote" => "community_notes/notes#vote"
  end

  # Notes ride along on every post. Invariants enforced here:
  # - authorship is never serialized (anonymous to members; DB keeps it for abuse response)
  # - open notes expose NO tallies (anti-bandwagon); accepted notes show agreement %
  # - open notes are members-only; an accepted note is visible to any viewer of the post
  add_to_serializer(:post, :community_notes, include_condition: -> { SiteSetting.community_notes_enabled }) do
    notes = ::CommunityNotes::Note.where(post_id: object.id).order(:created_at)
    my_votes =
      if scope.user
        ::CommunityNotes::NoteVote
          .where(note_id: notes.map(&:id), user_id: scope.user.id)
          .index_by(&:note_id)
      else
        {}
      end

    notes.filter_map do |note|
      accepted = note.accepted?
      next nil if !accepted && scope.user.nil?
      data = {
        id: note.id,
        category: note.category,
        body: note.body,
        accepted: accepted,
        mine: scope.user&.id == note.author_id,
        my_vote: my_votes[note.id]&.agree,
      }
      data[:agreement_percent] = note.agreement_percent if accepted
      data
    end
  end
end
