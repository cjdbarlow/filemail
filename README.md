# FilEmail

An AppleScript to periodically scan Apple Mail accounts and import recent emails into DEVONthink,preserving the mailbox folder hierarchy as a group hierarchy.

## How it works

The script runs on a schedule (via launchd). Each run it:

1. Opens the configured DEVONthink database
2. Iterates every non-excluded mailbox across all configured accounts  
This allows certain mailboxes (e.g. trash, inbox) to be excluded, preventing filling DEVONThink up with trash, or waiting until a message has been filed.
3. Finds messages received within the last `pHours` hours
4. Files each message into DEVONthink under a group matching the mailbox folder name (e.g. a message in `Receipts` lands in a DEVONthink group called `Receipts`)
5. Imports any downloaded attachments into an `Attachments` subgroup alongside the message


## Prerequisites

- Apple Mail
- [DEVONthink](https://www.devontechnologies.com/apps/devonthink) (any edition)

## Setup

After cloning the repo:

### 1. Create your config file

Copy the example config and fill in your values:

```sh
cp filemail.config.example filemail.config
```

`filemail.config` is `.gitignored` and will never be committed. Open it in any text editor:

|         Key          |                                                       Description                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `DATABASE_PATH`      | POSIX path to your `.dtBase2` database. Leave empty to use the DEVONthink global inbox.                                  |
| `INCLUDED_ACCOUNTS`  | Comma-separated Mail account names to scan. Must match exactly as shown in Mail.app.                                     |
| `EXCLUDED_MAILBOXES` | Comma-separated folder names to skip. Matched against the folder's own name, not its full path. No spaces around commas. |
| `HOURS`              | How far back to look for messages. Set to at least 1.5× your launchd run interval to avoid gaps at boundaries.           |

### 2. Install the launch agent

Copy `com.YOUR_USERNAME.filemail.plist` to `~/Library/LaunchAgents/`, then edit it to set your username and the absolute path to `filemail.scpt`:

```xml
<key>ProgramArguments</key>
<array>
    <string>/usr/bin/osascript</string>
    <string>/Users/YOURUSERNAME/path/to/filemail.scpt</string>
</array>
```

Update `StandardOutPath` and `StandardErrorPath` the same way, then load it:

```sh
launchctl load ~/Library/LaunchAgents/com.YOUR_USERNAME.filemail.plist
```

The agent runs every hour (`StartInterval: 3600`).

### 3. Test manually

```sh
osascript filemail.scpt
```

Check `filemail.log` (written next to the script) for a run summary.

## Logging

Each run appends timestamped lines to `filemail.log` in the same directory as the script. Useful entries:

- `=== filemail started ===` / `=== filemail finished ===` — run boundaries
- `Mailbox: FolderName — N recent message(s)` — per-mailbox summary
- `Filing: 'Subject' -> /FolderName/` — each message as it is filed
- `ERROR ...` — any failures

## Attribution

The per-message filing logic (`fileMessage` handler) is original DEVONthink code, based on "Mail Rule - File messages & attachments hierarchically" from Christian Grunenberg, Copyright © 2012–2020. All rights reserved.

The standalone run loop, mailbox scanner, recursive `processMailbox` handler, and logging are new additions.