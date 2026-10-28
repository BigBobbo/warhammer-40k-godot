# LLM critic screenshot restore — undoes shot_prep.gd: re-shows the hidden UI
# and movement trails, clears the suggestion overlay, restores the camera.
var m = tree.current_scene
for n in tree.root.get_meta("llm_critic_hidden", []):
	if is_instance_valid(n):
		n.visible = true
tree.root.remove_meta("llm_critic_hidden")
m._clear_ai_suggestion_overlay()
var view = tree.root.get_meta("llm_critic_view", [])
if view.size() == 2:
	m.restore_view_snapshot(view[0], view[1], false)
tree.root.remove_meta("llm_critic_view")
tree.root.remove_meta("llm_critic_decision")
return true
