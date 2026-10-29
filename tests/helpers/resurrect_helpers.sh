# we want "fixed" dimensions no matter the size of real display
set_screen_dimensions_helper() {
	stty cols 200
	stty rows 50
}

last_save_file_differs_helper() {
	local original_file="$1"
	diff "$original_file" "${HOME}/.tmux/resurrect/last"
	[ $? -ne 0 ]
}

# A fresh pane is titled with the host name, which no fixture can carry.
# Every shell the test environment opens announces the title "pane" first,
# so the saved title column is the same on every machine.
pin_pane_titles_helper() {
	cat >> ~/.tmux.conf <<-HERE
	set -g default-command "printf '\\033]2;pane\\007'; exec bash"
	HERE
}
