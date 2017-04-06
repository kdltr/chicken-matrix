A Matrix client in CHICKEN Scheme
=================================

Only the most basic features have been implemented:

- password login
- message receiving
- message sending
- emotes

The text user interface is very crude and has a few bugs.

If you want to support this project, consider donating [on liberapay](https://liberapay.com/Kooda/)!


How to use it
-------------

You have to start a new terminal that will be used by the client for its interface. I usually run `tty; sleep 9999999` in it so that I get the path to its pty and to make it ignore any input.

You then have to define the TTY environment variable in the shell you want to run the client, like so `export TTY=/dev/pts/N`, where N is the pty of the new terminal you opened.

At last, run `csi client.scm` in this directory and use the `(init! <server>)`, `(password-login <user> <password>)` and `(startup)` procedures, like so:

    (init! "https://upyum.com")
    (password-login "toto" "my-super-password")
    (startup)


You can quit by typing /exit at the input prompt, your session will be saved in `config.scm` and automatically loaded back next time so that you only have to run the `(startup)` procedure (or directly run `csi client.scm -e '(startup)'`).


Available commands
------------------

- `/me text` sends an emote
- `/rooms` lists the rooms you are in in the status bar
- `/room room-id` moves you to the given room
- `/exit` saves the session to config.scm and quits


TUI Roadmap and ideas
---------------------

- [x] Room participation
- [x] Session storage
- [ ] Programmable key bindings and commands
- [ ] Configurable external commands for media handling
- [ ] Low bandwidth mode (for mobile connection)
- [ ] Configurable notifications support (external command? sounds? terminal beep?)
- [ ] End to end encryption
    - [ ] Flat file for room keys, device keys and trusted keys for easy import/export
- [ ] Optional state/timeline persistent storage
- [ ] Configurable typing notifications
- [ ] Media sending
- UI design
    - [ ] Login screen
    - [ ] Easy (and lazy) room history navigation
    - [ ] Rooms grouping
    - [ ] Tiny screen support: N900 has a 79x18 terminal (79x21 fullscreen)
    - [ ] Big screen support (st fullscreen is 239x67 here)
    - [ ] Good color support (8, 16, 256, 24 bits)
        - [ ] Nickname coloration
        - [ ] Images thumbnails
    - Message display
        - [ ] Partial MXID showing when multiple display names are identical
        - [ ] Message date
        - [ ] Formated messages viewing
        - [ ] Contrast check for colored messages
        - [ ] Non-intrusive receipt indicators
    - Message / command composition
        - [ ] Formated message composition
        - [ ] Multi-lines messages with intelligent behaviour when pasting text
        - [ ] Typing suggestions / completion (like [this](https://asciinema.org/a/37390))
        - [ ] Suggestion menu / command submenu
    - Encryption
        - [ ] Good E2E key verification interface
        - [ ] Encryption validity indicator
    - [ ] Last read message indicator
    - [ ] Screen indicators when viewing older messages, with a way to quickly go back to the present
    - [ ] Room participants screen with actions menu (private message, kick, ban, …)
    - [ ] Message/events navigation with contextual actions (quote, open/save media, …)
    - [ ] Status bar with typing notifications, encryption status, other rooms status…
    - [ ] Room directory screen with easy access to other servers’ directory
