#!/usr/bin/env bash



source env.sh
is_prime() {
    if (( $1 < 3 )); then
        return 0
    fi
    s=$(seq 2 $(($1-1)))
    while IFS= read -r i; do
        if (( $1 % $i == 0 )); then
            return 1
        fi
    done<<<"$s"
    return 0
}

rm -fr wsr wsw o w seq g tty
mkfifo wsr
trap 'rm -fr wsr wsw w o g seq tty' EXIT
mkfifo wsw
mkdir o
mkdir g
mkdir w
websocat wss://gateway.discord.gg <wsw >wsr &
ln -s $(tty) tty
heartbeat() {
    sendmsg '{"op":1,"d":'$(cat seq)'}'
}
dbg() {
    echo "$@" >tty
}
sendmsg() {
    fn=$(mktemp -p w)
    echo "$@" > $fn
    ln -s "$(readlink -f $fn)" o
}

(
dbg subshell started
while [[ -d o ]]; do
    for m in $(find $(readlink -f o) -type l); do
        dbg Sending message $m
        cat $m
        dbg "$(cat $m)"
        rm $m
    done
done > wsw)&

(
while [[ -d o ]]; do
    dbg handshaking
    heartbeat 
    sleep 10
done
)&


test_guild() {
    dbg Testing guild $1
    nonce=$(mktemp -p g -d)
    sendmsg '{"op":8,"d":{"guild_id":"'$1'", "query":"", "limit":0,"nonce":"'$nonce'"}}'
}


dispatch() {
    event=$(echo "$1" | jq -r .t)
    dbg Dispatching event $event
    if [[ $event = GUILD_MEMBER_ADD ]] || [[ $event = GUILD_MEMBER_REMOVE ]] ; then
        guildid=$(echo "$1" | jq -r .d.guild_id)
        dbg Someone joined $guildid
        test_guild $guildid
    elif [[ $event = MESSAGE_CREATE ]]; then
        content="$(echo "$1"|jq -r .d.content)"
        dbg Received message
        case "$content" in 
            gtest*)
                guildid=$(echo $content | tr -d '\n gtes')
                test_guild $guildid
                ;;
        esac
    elif [[ $event = GUILD_MEMBERS_CHUNK ]]; then
        chunk_size=$(echo "$1" | jq -r '[.d.members[]]|length')
        nonce=$(echo "$1" | jq -r '.d.nonce')
        chunk_index=$(echo "$1"| jq -r '.d.chunk_index')
        chunk_count=$(echo "$1"| jq -r '.d.chunk_count')
        echo $chunk_size > $nonce/$chunk_index
        total_received=$(find $nonce -type f| wc -l)
        dbg "Received chunk $chunk_index/$chunk_count (total $total_received) of size $chunk_size for $nonce"
        if [[ $total_received -eq $chunk_count ]]; then
            total_member_count=$(cat $nonce/* | paste -sd+ - | bc)
            dbg "we are done for now. total members: $total_member_count"
            if is_prime $total_member_count; then
                dbg "prime number woohoooo sending message to $ANNOUNCEMENT"
                curl -X POST -H "Authorization: Bot $TOKEN" https://discord.com/api/v10/channels/$ANNOUNCEMENT/messages -F payload_json='{"content": "WOOOO BABY A PRIME NUMBER!! WE ARE NOW '$total_member_count' MEMBERS!!!! WOOO THATS WHAT IVE BEEN WAITING FOR"}' >/dev/null 2>/dev/null
            fi
        fi

    fi
}

echo null > seq
while true; do
    dbg Trying to read line
    if read -r line ; then 
        echo $line | jq 'if .s then .s else '"$(cat seq)"' end'>seq
        op=$(echo $line | jq .op)
        echo $line >> rawlog
        if [[ $op -eq 10 ]]; then
            sendmsg '{"op":2,"d":{"token":"'$TOKEN'", "properties":{"os":"linux","browser":"bash","device":"bash"},"presence":{"status":"online","afk":false, "activities":[{"type":0,"name":"Being coded in Bash"}]}, "intents":33287}}' # change intents back to 7
        elif [[ $op -eq 0 ]]; then
            dispatch "$line"
        elif [[ $op -eq 1 ]] || [[ $op -eq 10 ]]; then
            dbg Received heartbeat
            dbg New sequence number = $(cat seq)
        else 
            dbg Received message of type $op
        fi
    fi
done <wsr

