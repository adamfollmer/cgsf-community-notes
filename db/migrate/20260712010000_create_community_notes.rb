# frozen_string_literal: true

class CreateCommunityNotes < ActiveRecord::Migration[7.2]
  def change
    create_table :community_notes do |t|
      t.integer :post_id, null: false
      t.integer :author_id, null: false # kept for abuse response; never serialized
      t.string :category, null: false, limit: 20
      t.text :body, null: false
      t.timestamps
    end
    add_index :community_notes, :post_id
    add_index :community_notes, %i[post_id author_id], unique: true

    create_table :community_note_votes do |t|
      t.integer :note_id, null: false
      t.integer :user_id, null: false
      t.boolean :agree, null: false
      t.timestamps
    end
    add_index :community_note_votes, %i[note_id user_id], unique: true
  end
end
