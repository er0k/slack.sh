# slack.sh

Set your Slack status, presence and do-not-disturb from the shell.

If you are the current on-call, get a random status:

:feelsgood: :finnadie: :goberserk: :godmode: :hurtrealbad: :rage1: :rage2: :rage3: :rage4: :suspect: _on-call_

- `here`: here and not snoozed (dnd off). No status, unless you are on-call
- `away`: away and snoozed (dnd on) for 24 hours. If on-call, no snoozing
- `zzz`: here and snoozed (unless you are on-call)

Some other (maybe) useful statuses:

- `lunch`: away and snoozed for 1 hour. Random status of :pizza: :hamburger: :taco: :sandwich: :burrito: _Eating lunch_
- `brb`: away and snooze for 5 minutes. :walking: _afk brb_
- `dog`: away and snooze for 20 minutes. :walking-the-dog: _afk brb_
- `meet`: here and snoozed. :calendar: _In a meeting_
- `call`: here and snoozed. :telephone_receiver: _On a call_
- `pom`: here and snooze for 25 minutes. Useful for pomodoro.

other commands:

- `st`: get the current status, skipping cache
- `stc`: get the cached status (cache lives for 5 minutes)
- `moon`: a trip to the moon :new_moon_with_face:
- `auto`: run this in a cronjob to check if you are using the camera and set `meet` accordingly

## Install

1. Make sure `curl`, `jq`, `jo`, `pgrep` are available in your `$PATH`

2. Create a [new Slack App](https://api.slack.com/apps?new_app=1) from scratch

3. Grant your app the following OAuth scopes:

    - users.profile:read
    - users.profile:write
    - users:read
    - users:write
    - dnd:read
    - dnd:write

4. Install the app to your Workspace to get the OAuth token (probably need admin approval for this step, so ask nicely)

5. Get the necessary environment variables

    + `SLACK_USER_ID` from `https://<your-org>.slack.com/account/profile`
    + `SLACK_TOKEN` from step 4 above
    + `PD_USER_ID` from `https://<your-org>.pagerduty.com/users`
    + `PD_TOKEN` from My Profile > User Settings > Create API User Token
    + `PD_SHEDULE_ID` from `https://<your-org>.pagerduty.com/schedules`

6. Set the env vars:

    ```
    export SLACK_USER_ID="your-slack-id"
    export SLACK_TOKEN="your-slack-token"
    export PD_USER_ID="your-pagerduty-id"
    export PD_TOKEN="your-pagerduty-token"
    export PD_SHEDULE_ID="your-pagerduty-schedule-id"
    ```

## Usage

Run the script for usage instructions:

```
$ ./slack.sh
```

To run in a cronjob, you can use a tmux session with your env vars in it:

```
* 10-18 * * 1-5 tmux send -t cron "/path/to/slack.sh auto" ENTER > /dev/null 2>&1
```

To put your slack status in your tmux bar, do something like:

```
set-option -g status-right "\
#[fg=colour15, bg=colour240]\
#[fg=colour13, bg=colour237] #(/path/to/slack.sh stc) \
#[fg=colour15, bg=colour240]"
```

You may want to set an alias if are lazy and hate typing, like me:

```
alias sl='/path/to/slack.sh'
```
