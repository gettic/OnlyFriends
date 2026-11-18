# Only Friends

Declines party invites from players who are not your friends or in your guild. Made for WoW Forever.

> **Beta.** This is an early version. Please report anything odd.

## What it does

When someone invites you to a group, Only Friends checks who they are:

- If they are **trusted**, nothing changes. You see the normal invite and can accept or decline.
- If they are **not trusted**, the invite is declined for you and its window is closed. You get one chat line naming the player. Click the name to whisper or look them up.
- If you lead a group, a request to join it ("Name requests to join your group", including Quick Join) from someone who is not trusted is declined too, with one chat line. Suggestions from your own group members ("X wants to invite Y") are left for you to answer.

Examples:
- `Only Friends: declined a party invite from [Name].`
- `Only Friends: declined a request to join your group from [Name].`

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
| `/of` | Shows whether Only Friends is on or off, and the commands |
| `/of on` | Turns it on (this is the default) |
| `/of off` | Turns it off, so all invites show as normal |
| `/of minimap` | Hides or shows the minimap button |
| `/onlyfriends` | Same as `/of` |

The on/off setting and the button position are saved for your whole account, so they are the same on all your characters.

## Minimap button

| Action | What happens |
|---|---|
| Left-click | Turns Only Friends on or off |
| Drag | Moves the button round the minimap (the position is saved) |
| Hover | The tooltip says "On" or "Off" |

When it is off, the icon is greyed out with a red X. `/of minimap` hides or shows the button.

If your game shows Blizzard's addon menu on the minimap, Only Friends is in it too; left-click there turns it on or off.

Your on/off setting from earlier versions is kept.

## Installing

- **Addon manager:** add Only Friends and install it. To get this beta, choose the beta channel.
- **By hand:** download the zip from the Releases page, and unpack it so the `OnlyFriends` folder ends up in `Interface\AddOns` in your WoW folder. Restart the game or reload the UI (`/reload`).

## Known limits

- The invite **sound** and the **taskbar flash** still happen, because the game plays them before the addon can step in. The invite window itself is closed right away.
- Right after logging in, your guild list may not have loaded yet. Then the addon waits up to 3 seconds for it before deciding, so an invite from a guildmate is not declined by mistake. The invite window can stay up for that moment.
- If the guild list still hasn't loaded after those 3 seconds, the invite is declined.
- If you are already in a group, an invite from a stranger never shows as a popup (the game only prints a chat line), so there is nothing to decline.
- If a join request can't be declined, you get a chat note and the request stays for you to answer.
- An invite with no readable name or player ID is declined.
- If someone keeps inviting you, you get one chat line per player every 10 seconds, not one per invite.

## For people who change the code

The addon is the `OnlyFriends` folder:

| File | What it is |
|---|---|
| `OnlyFriends\OnlyFriends_Forever.toc` | Addon info (interface 16001, saved variable `OnlyFriendsDB`) |
| `OnlyFriends\OnlyFriends.lua` | All the code |
