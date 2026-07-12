import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import ProposeNoteModal from "../components/propose-note-modal";

export default class ProposeNoteButton extends Component {
  @service modal;
  @service siteSettings;

  @action
  propose() {
    this.modal.show(ProposeNoteModal, {
      model: {
        post: this.args.post,
        maxWords: this.siteSettings.community_notes_max_words,
      },
    });
  }

  <template>
    <DButton
      class="post-action-menu__community-note"
      @action={{this.propose}}
      @icon="note-sticky"
      @title="community_notes.add_note"
    />
  </template>
}
