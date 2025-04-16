#!/bin/bash
# set slack status/presence/dnd

# set these in your env
[ -n "$SLACK_USER_ID" ] || { echo "need a SLACK_USER_ID to continue"; exit 2; }
[ -n "$SLACK_TOKEN" ] || { echo "need a SLACK_TOKEN to continue"; exit 3; }

# set these if you want to check pagerduty
: "${PD_USER_ID:=nope}"
: "${PD_TOKEN:=nope}"
: "${PD_SHEDULE_ID:=nope}"

# cached slack status so we don't crush the API
STATUS_FILE=/tmp/slack_status

# check for necessary tools
tools="curl jq jo pgrep"
for tool in $tools; do
  command -v "$tool" > /dev/null || { echo "missing $tool, cannot continue"; exit 4; }
done

rand_food() {
  foods=("pizza" "hamburger" "taco" "sandwich" "burrito" "ramen")
  echo "${foods[$RANDOM % ${#foods[@]}]}"
}

rand_doom() {
  doom=("feelsgood" "finnadie" "goberserk" "godmode" "hurtrealbad" "rage1" "rage2" "rage3" "rage4" "suspect")
  echo "${doom[$RANDOM % ${#doom[@]}]}"
}

# https://api.slack.com/methods/users.profile.set
set_status() {
  status="${1:-}"
  emoji="${2:-}"
  echo -n "setting status ${status} ${emoji}.."
  [ -z "$emoji" ] || emoji="\:$emoji:"
  body_profile=$(jo profile="$(jo status_text="$status" status_emoji="$emoji" status_expiration=0)")
  curl -s -X POST \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    -d "${body_profile}" \
    https://slack.com/api/users.profile.set | jq .ok
  rm -f "${STATUS_FILE}"
}

# https://api.slack.com/methods/users.setPresence
set_presence() {
  pres="${1:-auto}" # auto or away
  echo -n "setting presence ${pres}.."
  body_presence=$(jo presence="$pres")
  curl -s -X POST \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    -d "${body_presence}" \
    https://slack.com/api/users.setPresence | jq .ok
}

get_presence() {
  curl -s \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    https://slack.com/api/users.getPresence \
    | jq -r .presence
}

get_status() {
  curl -s \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    https://slack.com/api/users.profile.get \
    | jq -r .profile.status_text # .profile.status_emoji
}

# snooze aka do-not-disturb
is_snoozing() {
  snoozing=$(curl -s -X POST \
  -H "Content-type: application/json; charset=utf-8" \
  -H "Authorization: Bearer ${SLACK_TOKEN}" \
  -H "X-Slack-User: ${SLACK_USER_ID}" \
  https://slack.com/api/dnd.info | jq .snooze_enabled)
  [[ "${snoozing}" == "true" ]]
}

snooze() {
  echo -n "snoozing for.."
  mins="${1:-1440}" # snooze for a day
  body_snooze=$(jo num_minutes="${mins}")
  curl -s -X POST \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    -d "${body_snooze}" \
    "https://slack.com/api/dnd.setSnooze" | jq .snooze_remaining
}

wake_up() {
  echo -n "waking up.."
  curl -s -X POST \
    -H "Content-type: application/json; charset=utf-8" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "X-Slack-User: ${SLACK_USER_ID}" \
    "https://slack.com/api/dnd.endSnooze" | jq .ok
}

is_linux() {
  [[ $(uname -s) == "Linux" ]]
}

is_mac() {
  [[ $(uname -s) == "Darwin" ]]
}

using_zoom() {
  if is_linux; then
    [[ $(pgrep -i zoom) ]] && return
  fi

  if is_mac; then
    [[ $(pgrep -i cpthost) ]] && return
  fi

  false
}

using_camera() {
  if is_linux; then
    # figure out how to check this
    return 1
  fi

  if is_mac; then
    log show --last 1s | grep -q cameracaptured && return
  fi

  false
}

is_oncall() {
  [ "$PD_USER_ID" = "nope" ] && return 1
  [ "$PD_TOKEN" = "nope" ] && return 1
  [ "$PD_SHEDULE_ID" = "nope" ] && return 1
  oncall_id=$(curl -s \
    -H "Authorization: Token token=$PD_TOKEN" \
    "https://api.pagerduty.com/oncalls?schedule_ids[]=$PD_SHEDULE_ID" \
    | jq -r .oncalls[1].user.id \
  )
  if [[ "$oncall_id" == "$PD_USER_ID" ]]; then
    echo "you're on call. hooray"
    return
  else
    false
  fi
}

idle_time() {
  if is_linux; then
    echo $(($(xssstate -i) / 1000))
  fi

  if is_mac; then
    /usr/sbin/ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000)}'
  fi
}

get_live_status() {
  snooze=$(is_snoozing && echo "🔕" || echo "")
  presence=$([ $(get_presence) == "away" ] && echo "🔴" || echo "🟢")
  echo "${presence} ${snooze} $(get_status)" > "${STATUS_FILE}"
}

get_cached_status() {
  if [ ! -f "${STATUS_FILE}" ]; then
    get_live_status
  fi

  # 5 minutes
  if [ $(stat --format=%Y "${STATUS_FILE}") -le $(( `date +%s` - (5*60) )) ]; then
    get_live_status
  fi
}

case "$1" in
  auto)
    status="$(get_status)"
    if using_camera; then
      echo "on cam, probably in a meeting"
      if [[ "${status}" == "In a meeting" ]]; then
        echo "already in a meeting"
      else
        $0 meet
      fi
    else
      if [[ "${status}" == "In a meeting" ]]; then
        $0 here
      fi
    fi
    ;;
  here)
    wake_up
    set_presence
    if is_oncall; then
      set_status "on-call" "$(rand_doom)"
    else
      set_status
    fi
    ;;
  away)
    set_presence away
    if is_oncall; then
      set_status "on-call" "$(rand_doom)"
      wake_up
    else
      set_status
      snooze
    fi
    ;;
  lunch)
    set_presence away
    set_status "Eating lunch" "$(rand_food)"
    snooze 60
    ;;
  brb)
    set_presence away
    set_status "afk brb" "walking"
    snooze 5
    ;;
  dog)
    set_presence away
    set_status "afk brb" "walking-the-dog"
    snooze 20
    ;;
  meet)
    set_presence auto
    set_status "In a meeting" "calendar"
    snooze
    ;;
  call)
    set_presence auto
    set_status "On a call" "telephone_receiver"
    snooze
    ;;
  zzz)
    set_presence auto
    if is_oncall; then
      set_status "on-call" "$(rand_doom)"
      echo "sorry, no snoozing. You are on-call."
      wake_up
    else
      set_status
      snooze
    fi
    ;;
  st)
    get_live_status
    cat "${STATUS_FILE}"
    ;;
  stc)
    get_cached_status
    cat "${STATUS_FILE}"
    ;;
  pom)
    snooze 25
    ;;
  moon)
    emojis="new_moon waxing_crescent_moon first_quarter_moon moon full_moon waning_gibbous_moon last_quarter_moon waning_crescent_moon new_moon_with_face"
    for emoji in $emojis; do
      set_status "..." "${emoji}"
      sleep 3
    done
    set_status
    ;;
  *)
    echo "Usage: $0 [here|away|zzz|lunch|brb|dog|meet|call|pom|st|stc|auto|moon]"
    exit 1
    ;;
esac
