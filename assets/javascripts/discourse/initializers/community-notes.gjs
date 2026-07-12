import { withPluginApi } from "discourse/lib/plugin-api";
import CommunityNotesSection from "../components/community-notes-section";
import ProposeNoteButton from "../components/propose-note-button";

export default {
  name: "community-notes",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.community_notes_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addTrackedPostProperties("community_notes");

      // Accepted + open notes render under the post body
      api.renderAfterWrapperOutlet("post-content-cooked-html", CommunityNotesSection);

      // "Add community note" in the post action menu — members only, never on your own post
      const currentUser = api.getCurrentUser();
      api.registerValueTransformer(
        "post-menu-buttons",
        ({ value: dag, context: { post, firstButtonKey } }) => {
          if (!currentUser || !post || post.user_id === currentUser.id || post.post_type !== 1) {
            return;
          }
          dag.add("community-note", ProposeNoteButton, { before: firstButtonKey });
        }
      );
    });
  },
};
