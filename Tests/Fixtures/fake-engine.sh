#!/bin/zsh
# Replays canned sidecar protocol lines. FAKE_MODE=crash exits abruptly after two updates.
# A stdin line makes it write FAKE_MARK (if set), print the Cancelled error and exit 2.
# FAKE_STDERR, when set, is written to stderr first.
[[ -n "$FAKE_STDERR" ]] && echo "$FAKE_STDERR" >&2
case "$1" in
  devices) echo '{"type":"devices","auto":0,"devices":[{"index":0,"name":"CPU","backend":"CPU","integrated":false,"memory_total":0}]}' ;;
  instruments) echo '{"type":"instruments","instruments":[{"name":"acoustic_piano","program":0},{"name":"drums","program":128}]}' ;;
  transcribe)
    echo '{"type":"load","progress":0.5}'
    echo '{"type":"ready","device":{"index":0,"name":"CPU","backend":"CPU"},"chunks":3}'
    for i in 1 2 3; do
      echo "{\"type\":\"update\",\"progress\":$((i * 33)).0e-2,\"finalized_through\":$((i * 5)).0,\"notes\":[{\"onset\":$i.0,\"offset\":$i.5,\"pitch\":6$i,\"program\":0,\"is_drum\":false,\"instrument\":\"acoustic_piano\"}]}"
      if [[ "$FAKE_MODE" == crash && $i == 2 ]]; then kill -9 $$; fi
      if read -t 0.4 -r _; then
        [[ -n "$FAKE_MARK" ]] && : > "$FAKE_MARK"
        echo '{"type":"error","code":"Cancelled","message":"cancelled by host"}'
        exit 2
      fi
    done
    echo '{"type":"done","note_count":3}' ;;
esac
