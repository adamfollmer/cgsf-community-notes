# frozen_string_literal: true

require "rails_helper"

RSpec.describe "cgsf-community-notes", type: :request do
  fab!(:author) do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    Fabricate(:user, name: nil)
  end
  fab!(:proposer) { Fabricate(:user, name: nil) }
  fab!(:voters) { 4.times.map { Fabricate(:user, name: nil) } }
  fab!(:topic) { Fabricate(:topic, user: author) }
  fab!(:post_record) { Fabricate(:post, topic: topic, user: author) }

  before do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    SiteSetting.civic_pacing_enabled = false if SiteSetting.respond_to?(:civic_pacing_enabled)
    SiteSetting.community_notes_enabled = true
    SiteSetting.community_notes_quorum_floor = 3
    SiteSetting.community_notes_agreement_percent = 67
  end

  def propose(user, body: "This claim needs a source — the budget PDF says otherwise.", category: "correction")
    sign_in(user)
    post "/community-notes.json", params: { post_id: post_record.id, category: category, body: body }
  end

  def cast_vote(user, note_id, agree)
    sign_in(user)
    put "/community-notes/#{note_id}/vote.json", params: { agree: agree }
  end

  def note
    ::CommunityNotes::Note.last
  end

  it "lets a member propose a note on someone else's post" do
    propose(proposer)
    expect(response.status).to eq(200)
    expect(note.category).to eq("correction")
  end

  it "never allows noting your own post" do
    propose(author)
    expect(response.status).to eq(403)
  end

  it "rejects a second note from the same member on the same post" do
    propose(proposer)
    propose(proposer, body: "Another angle on the same post entirely.")
    expect(response.status).to eq(422)
  end

  it "enforces the word limit" do
    propose(proposer, body: (["word"] * 101).join(" "))
    expect(response.status).to eq(422)
  end

  it "rejects invalid categories" do
    propose(proposer, category: "takedown")
    expect(response.status).to eq(422)
  end

  it "accepts a note at quorum + supermajority, then closes voting" do
    propose(proposer)
    cast_vote(voters[0], note.id, true)
    cast_vote(voters[1], note.id, true)
    expect(note.accepted?).to eq(false) # below quorum of 3

    cast_vote(voters[2], note.id, true)
    expect(note.accepted?).to eq(true) # 3 votes, 100% agreement

    cast_vote(voters[3], note.id, false)
    expect(response.status).to eq(422) # voting closed at acceptance
    expect(note.note_votes.count).to eq(3)
  end

  it "does not accept without supermajority" do
    propose(proposer)
    cast_vote(voters[0], note.id, true)
    cast_vote(voters[1], note.id, false)
    cast_vote(voters[2], note.id, false)
    expect(note.accepted?).to eq(false)
  end

  it "allows changing a vote while open" do
    propose(proposer)
    cast_vote(voters[0], note.id, false)
    cast_vote(voters[0], note.id, true)
    expect(note.note_votes.count).to eq(1)
    expect(note.note_votes.first.agree).to eq(true)
  end

  it "does not let the note author vote on their own note" do
    propose(proposer)
    cast_vote(proposer, note.id, true)
    expect(response.status).to eq(403)
  end

  describe "serialization invariants" do
    before { propose(proposer) }

    def serialized_notes(viewer)
      serializer = PostSerializer.new(post_record.reload, scope: Guardian.new(viewer), root: false)
      serializer.as_json[:community_notes]
    end

    it "never exposes the author, and hides tallies while voting is open" do
      data = serialized_notes(voters[0]).first
      expect(data.keys).not_to include(:author_id, :user_id)
      expect(data.keys).not_to include(:agreement_percent)
      expect(data[:accepted]).to eq(false)
    end

    it "shows agreement percent only once accepted" do
      3.times { |i| cast_vote(voters[i], note.id, true) }
      data = serialized_notes(voters[0]).first
      expect(data[:accepted]).to eq(true)
      expect(data[:agreement_percent]).to eq(100)
    end

    it "hides open notes from logged-out viewers, shows accepted ones" do
      expect(serialized_notes(nil)).to eq([])
      3.times { |i| cast_vote(voters[i], note.id, true) }
      expect(serialized_notes(nil).length).to eq(1)
    end

    it "quorum scales with membership but respects the floor" do
      expect(::CommunityNotes::Note.quorum).to eq(3) # floor, small test population
    end
  end
end
