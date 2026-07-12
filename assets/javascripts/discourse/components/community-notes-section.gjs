import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { eq } from "truth-helpers";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class CommunityNotesSection extends Component {
  static shouldRender(args) {
    return !!args.post?.community_notes?.length;
  }

  @service currentUser;

  get notes() {
    return this.args.post.community_notes || [];
  }

  // Accepted notes: highest agreement leads (the "primary" convention)
  get acceptedNotes() {
    return this.notes
      .filter((n) => n.accepted)
      .sort((a, b) => (b.agreement_percent || 0) - (a.agreement_percent || 0));
  }

  get openNotes() {
    return this.currentUser ? this.notes.filter((n) => !n.accepted) : [];
  }

  categoryLabel(note) {
    return i18n(`community_notes.categories.${note.category}`);
  }

  @action
  async vote(note, agree) {
    try {
      const result = await ajax(`/community-notes/${note.id}/vote`, {
        type: "PUT",
        data: { agree },
      });
      this.args.post.community_notes = this.notes.map((n) =>
        n.id === note.id ? { ...n, my_vote: agree, accepted: result.accepted } : n
      );
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    <div class="community-notes">
      {{#each this.acceptedNotes as |note|}}
        <div class="community-note --accepted">
          <div class="community-note__header">
            <span class="community-note__label">{{i18n "community_notes.accepted_label"}}</span>
            <span class="community-note__category">{{this.categoryLabel note}}</span>
            <span class="community-note__agreement">{{i18n
                "community_notes.agreement"
                percent=note.agreement_percent
              }}</span>
          </div>
          <p class="community-note__body">{{note.body}}</p>
        </div>
      {{/each}}

      {{#each this.openNotes as |note|}}
        <div class="community-note --open">
          <div class="community-note__header">
            <span class="community-note__label">{{i18n "community_notes.pending_label"}}</span>
            <span class="community-note__category">{{this.categoryLabel note}}</span>
          </div>
          <p class="community-note__body">{{note.body}}</p>
          {{#if note.mine}}
            <p class="community-note__mine">{{i18n "community_notes.your_note"}}</p>
          {{else}}
            <div class="community-note__vote">
              <DButton
                @action={{fn this.vote note true}}
                @label="community_notes.agree"
                @icon="check"
                class={{if (eq note.my_vote true) "btn-primary" "btn-default"}}
              />
              <DButton
                @action={{fn this.vote note false}}
                @label="community_notes.disagree"
                @icon="xmark"
                class={{if (eq note.my_vote false) "btn-danger" "btn-default"}}
              />
            </div>
          {{/if}}
        </div>
      {{/each}}
    </div>
  </template>
}
