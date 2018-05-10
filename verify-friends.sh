#!/bin/bash

# This script verifies that no user-provided links to "Friends of Rust" are
# broken. It does so by making a HTTP request to each website and looking at
# the status code of the response.
#
# If the request responds with 5xx the script terminates with a status code of
# 1, meaning a link is broken. 3xx and 4xx responses are treated as warnings
# and are simply logged, because they do not guarantee that there is something
# wrong with the requested website. The status code 000 is also treated as a
# warning because the status code alone does not specify where the problem
# lies, only that there is a problem, read more here: https://tinyurl.com/superuser-status-code-000
#
### Dependencies
# - curl
# - GNU parallel
#
### Usage
#
#  /bin/bash ./verify-links.sh
#
### Improvements to be made
# - Output the actual problem if the response status code was 000 (see link
#   above for more info)
#
# Author: http://github.com/simeg
# License: MIT
#

readonly SOURCE_FILE_URL="https://raw.githubusercontent.com/rust-lang/rust-www/master/_data/users.yml"
readonly JOBS_COUNT=100

# https://stackoverflow.com/questions/5014632/how-can-i-parse-a-yaml-file-from-a-linux-shell-script
parse_yaml() {
  local s fs
  s='[[:space:]]*' w='[a-zA-Z0-9_]*'
  fs=$(echo @|tr @ '\034')
  sed -ne "s|^\($s\):|\1|" \
    -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
    -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
    awk -F"$fs" '{
  indent = length($1)/2;
  vname[indent] = $2;
  for (i in vname) {if (i > indent) {delete vname[i]}}
    if (length($3) > 0) {
      vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
      if ($2 == "url") {
        printf("%s,", $3);
      }
    }
  }'
}

echo "Fetching source file.."
readonly FRIENDS_FILE=$(mktemp)
curl --silent "${SOURCE_FILE_URL}" > "$FRIENDS_FILE"
echo "OK!"

echo "Parsing URLs from file.."
readonly URLS=$(parse_yaml "$FRIENDS_FILE")
echo "OK!"

### Convert file to array
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash
IFS=',' read -ra URL_ARRAY <<< "$URLS"

# Write URLs to file
readonly RAW_URLS_FILE=$(mktemp)
printf "%s\\n" "${URL_ARRAY[@]}" > "$RAW_URLS_FILE"

curl_for_status_code() {
  local url="$1"
  local status_code=

  status_code=$(
  curl "$url" \
    --silent \
    --max-time 5 \
    -L \
    --write-out "%{http_code}" \
    --output /dev/null
  )
  printf "%s\\t%d\\n" "$url" "$status_code"
}

# Make function available for parallel
export -f curl_for_status_code

printf "Found [ %s ] URLs, cURLing them...\\n" "$(wc -l < "$RAW_URLS_FILE")"

URLS_WITH_STATUSES_FILE=$(mktemp)
parallel --jobs $JOBS_COUNT curl_for_status_code < "$RAW_URLS_FILE" >> "$URLS_WITH_STATUSES_FILE"

cat "$URLS_WITH_STATUSES_FILE" | while read RESULT
do
  URL=$(echo "$RESULT" | cut -f1)
  STATUS_CODE=$(echo "$RESULT" | cut -f2)
  FIRST_DIGIT=${STATUS_CODE:0:1}

  case "$FIRST_DIGIT" in
    "2")
      echo OK!
      ;;
    "3" | "4" | "0")
      printf "WARNING: URL [ %s ] responded with status code [ %d ], continuing..\\n" "$URL" "$STATUS_CODE"
      ;;
    "5")
      printf "ERROR: URL [ %s ] responded with status code [ %d ], aborting!\\n" "$URL" "$STATUS_CODE"
      exit 1
      ;;
    *)
      printf "UNKNOWN STATUS CODE: URL [ %s ] responded with status code [ %d ], continuing..\\n" "$URL" "$STATUS_CODE"
      echo "UNKNOWN"
      ;;
  esac
done
