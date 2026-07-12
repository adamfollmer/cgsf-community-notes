import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq, gt } from "truth-helpers";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const CATEGORIES = ["correction", "conduct", "placement", "duplicate", "scam"];

export default class ProposeNoteModal extends Component {
  @tracked body = "";
  @tracked category = "correction";
  @tracked saving = false;

  categories = CATEGORIES;

  get maxWords() {
    return this.args.model.maxWords || 100;
  }

  get wordCount() {
    return this.body.trim() === "" ? 0 : this.body.trim().split(/\s+/).length;
  }

  get disabled() {
    return this.saving || this.wordCount === 0 || this.wordCount > this.maxWords;
  }

  categoryLabel(cat) {
    return i18n(`community_notes.categories.${cat}`);
  }

  @action
  updateBody(event) {
    this.body = event.target.value;
  }

  @action
  updateCategory(event) {
    this.category = event.target.value;
  }

  @action
  async submit() {
    this.saving = true;
    const post = this.args.model.post;
    try {
      const result = await ajax("/community-notes", {
        type: "POST",
        data: { post_id: post.id, category: this.category, body: this.body },
      });
      post.community_notes = [
        ...(post.community_notes || []),
        {
          id: result.note_id,
          category: this.category,
          body: this.body,
          accepted: false,
          mine: true,
          my_vote: null,
        },
      ];
      this.args.closeModal();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "community_notes.modal_title"}}
      @closeModal={{@closeModal}}
      class="propose-note-modal"
    >
      <:body>
        <p class="propose-note-modal__hint">{{i18n "community_notes.modal_hint"}}</p>
        <label>{{i18n "community_notes.category"}}</label>
        <select {{on "change" this.updateCategory}} class="propose-note-modal__category">
          {{#each this.categories as |cat|}}
            <option value={{cat}} selected={{eq cat this.category}}>
              {{this.categoryLabel cat}}
            </option>
          {{/each}}
        </select>
        <textarea
          {{on "input" this.updateBody}}
          class="propose-note-modal__body"
          placeholder={{i18n "community_notes.body_placeholder"}}
          rows="5"
        >{{this.body}}</textarea>
        <div class="propose-note-modal__count {{if (gt this.wordCount this.maxWords) '--over'}}">
          {{i18n "community_notes.words" count=this.wordCount max=this.maxWords}}
        </div>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @label="community_notes.submit"
          @disabled={{this.disabled}}
          class="btn-primary"
        />
        <DButton @action={{@closeModal}} @label="community_notes.cancel" class="btn-flat" />
      </:footer>
    </DModal>
  </template>
}
