#!/bin/bash

REPLY_FILE="replies.txt"
BOT_NAME="Martin"
UNKNOWN="I don't know what to say."
USER_FILE="username.txt"

# Silence all error messages
exec 2>/dev/null

# Trim spaces safely
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Clean input: lowercase + remove punctuation
clean_text() {
    echo "$1" | tr 'A-Z' 'a-z' | tr -cd '[:alnum:] [:space:]' | xargs
}

# Load username if exists
if [[ -f "$USER_FILE" ]]; then
    USER_NAME=$(<"$USER_FILE")
else
    USER_NAME=""
fi

# Conversation state
STATE="idle"
MOOD=""

echo "$BOT_NAME: I'm here. Type 'exit' to quit."

while true; do
    # --- Dynamic prompt: show username if known ---
    if [[ -n "$USER_NAME" ]]; then
        read -p "$USER_NAME: " input 2>/dev/null
    else
        read -p "You: " input 2>/dev/null
    fi

    input=$(clean_text "$input")
    [[ "$input" == "exit" ]] && echo "$BOT_NAME: Bye." && break

    # --- Username memory / confirmation ---
    if [[ -z "$USER_NAME" ]]; then
        if [[ "$STATE" == "idle" ]]; then
            echo "$BOT_NAME: Hi! What's your name?"
            STATE="waiting_for_name"
            continue
        elif [[ "$STATE" == "waiting_for_name" ]]; then
            TEMP_NAME="$input"
            echo "$BOT_NAME: So your name is $TEMP_NAME, right? (yes/no)"
            STATE="confirming_name"
            continue
        elif [[ "$STATE" == "confirming_name" ]]; then
            if [[ "$input" =~ ^yes$ ]]; then
                USER_NAME="$TEMP_NAME"
                echo "$USER_NAME" > "$USER_FILE"
                STATE="idle"
                echo "$BOT_NAME: Great, I'll remember your name!"
            else
                STATE="waiting_for_name"
                echo "$BOT_NAME: Okay, let's try again. What's your name?"
            fi
            continue
        fi
    fi

    # --- Mood Event Flow (only "feeling" + four emotions) ---
    if [[ "$STATE" == "idle" ]]; then
        for emo in sad happy angry conf; do
            if [[ "$input" == *"feeling $emo"* ]]; then
                MOOD="$emo"
                STATE="waiting_for_mood_reply"
                case "$emo" in
                    sad) echo "$BOT_NAME: $USER_NAME, Sad huh? Talk about it, what made you sad?" ;;
                    happy) echo "$BOT_NAME: $USER_NAME, Looks like someone is in a good mood today, spill the beans bro" ;;
                    angry) echo "$BOT_NAME: $USER_NAME, Angry? Ok let me hear you rant about it, I got all day" ;;
                    conf) echo "$BOT_NAME: $USER_NAME, Yeah thats what I'm talking about, so what made you feel that today?" ;;
                esac
                continue 2
            fi
        done
    elif [[ "$STATE" == "waiting_for_mood_reply" ]]; then
        case "$MOOD" in
            sad) echo "$BOT_NAME: $USER_NAME, I’m really glad you told me. That must be tough." ;;
            happy) echo "$BOT_NAME: $USER_NAME, I’m glad you shared that with me! That’s wonderful." ;;
            angry) echo "$BOT_NAME: $USER_NAME, I understand. I hope the rant helps a bit." ;;
            conf) echo "$BOT_NAME: $USER_NAME, I understand. Confidence is good to express." ;;
        esac
        STATE="idle"
        continue
    fi

    # --- Suggest + emotion override (only four emotions) ---
    if [[ "$input" == *"suggest"* ]]; then
        for emo in sad happy angry conf; do
            if [[ "$input" == *"$emo"* ]]; then
                replies_for_emo=()
                while IFS='|' read type key priority reply; do
                    type=$(trim "$(clean_text "$type")")
                    key=$(trim "$(clean_text "$key")")
                    reply=$(trim "$reply")
                    if [[ "$key" == "$emo" && -n "$reply" ]]; then
                        replies_for_emo+=("$reply")
                    fi
                done < "$REPLY_FILE"

                n=${#replies_for_emo[@]}
                if [ $n -gt 0 ]; then
                    index=$((RANDOM % n))
                    echo "$BOT_NAME: ${replies_for_emo[$index]}"
                    continue 2
                fi
            fi
        done
    fi

    # --- Normal priority + combined replies + random per keyword ---
    keys_found=()
    priorities=()
    replies_found=()

    while IFS='|' read type key priority reply; do
        type=$(trim "$(clean_text "$type")")
        key=$(trim "$(clean_text "$key")")
        priority=$(trim "$priority")
        reply=$(trim "$reply")

        if [[ -n "$key" && -n "$reply" && "$input" == *"$key"* ]]; then
            # check if key already stored
            found=0
            for i in "${!keys_found[@]}"; do
                if [[ "${keys_found[i]}" == "$key" ]]; then
                    replies_found[i]+=$'\n'"$reply"
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                keys_found+=("$key")
                priorities+=("$priority")
                replies_found+=("$reply")
            fi
        fi
    done < "$REPLY_FILE"

    if [ ${#keys_found[@]} -eq 0 ]; then
        echo "$BOT_NAME: $UNKNOWN"
        continue
    fi

    # Find max priority safely
    max_priority=-1
    for p in "${priorities[@]}"; do
        (( p > max_priority )) 2>/dev/null && max_priority=$p
    done

    # Combine replies with max priority, pick random per keyword
    output=""
    for i in "${!keys_found[@]}"; do
        if [[ "${priorities[i]}" -eq "$max_priority" ]]; then
            IFS=$'\n' read -r -a options <<< "${replies_found[i]}"
            n=${#options[@]}
            if [ $n -gt 0 ]; then
                index=$((RANDOM % n))
                reply="${options[$index]}"
                
                # Append username if priority is 0
                if [[ "${priorities[i]}" -eq 0 && -n "$USER_NAME" ]]; then
                    reply="$reply, $USER_NAME"
                fi

                output+="$reply "
            fi
        fi
    done

    output=$(echo "$output" | xargs)
    if [[ -n "$output" ]]; then
        echo "$BOT_NAME: $output"
    else
        echo "$BOT_NAME: $UNKNOWN"
    fi

done
