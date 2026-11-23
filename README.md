# slack-gw

Watch a Slack workspace live, read it, and reply as yourself, from the terminal or from an agent. No Slack app, no admin rights, no open browser tab.

- One small daemon (systemd user service `slack-gw`) keeps one websocket open to Slack and saves every message, edit, delete, reaction, thread reply and file of your conversations in a local SQLite store.
- `read`, `wait` and `thread` read that store. `wait` blocks until something new comes in, so an agent can ask a question and wait for the answer.
- `send` and `reply` post as you, only to the channels you allow in the config.

## How it works

Slack's web client logs in with a session token (`xoxc-...`) plus the `d` cookie (`xoxd-...`). `slack-gw login` copies both from your logged-in browser once, with [browser-harness](https://github.com/browser-use/browser-harness). After that there is no browser:

| Part | Call |
|---|---|
| Live events | `rtm.connect` gives a `wss://` URL. One websocket, a `ping` every 30 s. |
| Read | `conversations.history`, `conversations.replies`, `users.list`, `users.conversations` |
| Send / reply | `chat.postMessage` (thread reply: `thread_ts`) |
| Files | `files.getUploadURLExternal`, upload, `files.completeUploadExternal` |
| Downloads | `url_private` with the token and the cookie |

The same flow with plain `curl` and `websocat`:

```sh
A=~/.config/slack-gw/auth.json
TOKEN=$(jq -r .token $A); D=$(jq -r .d $A); DOM=$(jq -r .domain $A)
api() { m=$1; shift; curl -s "https://$DOM.slack.com/api/$m" -H "Cookie: d=$D" --data-urlencode "token=$TOKEN" "$@"; }
api auth.test | jq '{ok, user, team}'
URL=$(api rtm.connect | jq -r .url)
websocat -t "$URL" -H "Cookie: d=$D"
```

Put the URL first: `websocat` 1.x reads a URL after `-H` as a second header.

## Install

```sh
./install.sh                      # links bin/slack-gw into ~/.local/bin, installs the unit, creates the config
$EDITOR ~/.config/slack-gw/config.json
slack-gw login                    # Chrome/Brave may ask "Allow remote debugging?": click Allow
systemctl --user enable --now slack-gw
slack-gw status
```

Needs `uv` (the script runs with `uv run --script`), `browser-harness` for `login`, and a browser that is logged in to the workspace.

`~/.config/slack-gw/config.json`:

| Key | Meaning |
|---|---|
| `team_id` | the workspace id (`T...`, it is in the `app.slack.com/client/T.../...` URL) |
| `default_channel` | the channel that `read`, `thread`, `send` and `wait` use when you give no `--channel` |
| `send_channels` | the only channels that `send` and `reply` can post to. Empty = no sends. |
| `channels` | record only these conversations. Empty = every conversation you are a member of. |

Local files, never in git: `~/.config/slack-gw/auth.json` (the session, mode 600), `~/.local/state/slack-gw/slack.db` and `media/`.

## Commands

```sh
slack-gw status                                   # listener state, every conversation, cursors
slack-gw read --channel dev --last 20             # top-level messages (threads: see thread)
slack-gw thread 1795424604.468059                 # a message and all its replies
slack-gw wait --channel all --others              # block until someone else writes anywhere
slack-gw wait --channel dev --since TS --others   # answers after your message TS
slack-gw reply TS "text"                          # reply in the thread of TS, not in the channel
slack-gw send "text" --file before.png --file after.png
echo "text" | slack-gw send -                     # text from stdin
slack-gw media TS                                 # local paths of the files of a message
slack-gw login                                    # new session when Slack logs you out
```

`--channel` takes an id or a part of the name. `wait` exits 0 with new events, 5 at the timeout, 4 when the listener is down and 3 when Slack refused the session (run `slack-gw login`). Each output ends with the next `wait --cursor N` command, so a loop never misses an event.

## Agent flow: watch, draft, reply in the thread

This is how I let an agent handle a team channel for me:

1. Run `slack-gw wait --channel <team channel> --others --timeout 60m` in the background. When it exits, start it again with the `--cursor` that it printed.
2. For each new message, show it to me with its `ts`, who wrote it, and what it answers (read the thread with `slack-gw thread TS` when it is a reply).
3. Draft an answer in my own voice (a private style file, not in this repo). Short, casual, no promises for me.
4. Post only after my yes on the exact text.
5. Always answer in the thread of the message: `slack-gw reply <ts of that message> "text"`. If the message is already a thread reply, use the thread root. Never post the answer in the channel, and do not use `--broadcast`.

`send_channels` is the hard stop: the tool refuses a post to any other channel.

## Limits

- `login` needs the browser once, and again when the session expires (Slack login has password, SSO and 2FA steps).
- The session is your own account. Anything the tool sends is from you.
- `rtm.connect` with a browser session works today; Slack can change that.
