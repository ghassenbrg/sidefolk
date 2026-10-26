#!/bin/sh
# Today, a Sidefolk extension template in plain sh (Sidefolk runs /bin/sh).
# MCP over stdio: one JSON-RPC message per line in, one per line out, nothing else on stdout.
# The sandbox lets a shell script run only the programs listed under permissions.exec (here /bin/date):
# even `head` or `sed` fail unless listed, so keep to shell built-ins for parsing.
# Sidefolk sends compact JSON with sorted keys, so "id" comes first in every request.

reply() { printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$1" "$2"; }

while IFS= read -r line; do
  case "$line" in *'"id":'*) ;; *) continue ;; esac        # notifications need no answer
  id=${line#*\"id\":}; id=${id%%,*}
  method=${line#*\"method\":\"}; method=${method%%\"*}
  case "$method" in
    initialize)
      reply "$id" '{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"today","version":"0.1.0"}}' ;;
    ping)
      reply "$id" '{}' ;;
    tools/list)
      reply "$id" '{"tools":[{"name":"today","title":"Today'"'"'s date","description":"The date today, spelled out.","inputSchema":{"type":"object","properties":{},"additionalProperties":false}}]}' ;;
    tools/call)
      today=$(/bin/date "+%A %e %B %Y")
      reply "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"Today is $today.\"}]}" ;;
    *)
      printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\n' "$id" ;;
  esac
done
