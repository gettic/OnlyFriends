# Only Friends

Declines party invites from players who are not your friends or in your guild. Made for WoW Forever.

> **Beta.** This is an early version. Please report anything odd.

## What it does

When someone invites you to a group, Only Friends checks who they are:

- If they are **trusted**, nothing changes. You see the normal invite and can accept or decline.
- If they are **not trusted**, the invite is declined for you and its window is closed. You get one chat line naming the player. Click the name to whisper or look them up.

Example: `Only Friends: declined a party invite from [Name].`

Nothing else is blocked. Whispers, trades and guild invites are not touched.

## Who counts as trusted

| Who | Trusted |
|---|---|
| Players on your WoW friends list | Yes |
| Your Battle.net friends | Yes |
| Members of your guild | Yes |
| Everyone else | No, the invite is declined |

## Party Sync invites

Party Sync invites from players who are not trusted are **not** declined. You only get a chat note, and the Party Sync window stays up so you can answer it yourself.

## Commands

| Command | What it does |
|---|---|
| `/of` | Shows whether Only Friends is on or off |
| `/of on` | Turns it on (this is the default) |
| `/of off` | Turns it off, so all invites show as normal |
| `/onlyfriends` | Same as `/of` |

The setting is saved for your whole account, so it is the same on all your characters.

## Installing

- **Addon manager:** add Only Friends and install it. To get this beta, choose the beta channel.
- **By hand:** download the zip from the Releases page, and unpack it so the `OnlyFriends` folder ends up in `Interface\AddOns` in your WoW folder. Restart the game or reload the UI (`/reload`).

## Known limits

- The invite **sound** and the **taskbar flash** still happen, because the game plays them before the addon can step in. The invite window itself is closed right away.
- Right after logging in, your guild list may not have loaded yet. Then the addon waits up to 3 seconds for it before deciding, so an invite from a guildmate is not declined by mistake. The invite window can stay up for that moment.
- If the guild list still hasn't loaded after those 3 seconds, the invite is declined.
- An invite with no readable name or player ID is declined.
- If someone keeps inviting you, you get one chat line per player every 10 seconds, not one per invite.

## For people who change the code

The addon is the `OnlyFriends` folder:

| File | What it is |
|---|---|
| `OnlyFriends\OnlyFriends_Forever.toc` | Addon info (interface 16001, saved variable `OnlyFriendsDB`) |
| `OnlyFriends\OnlyFriends.lua` | All the code |
