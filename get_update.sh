#!/bin/sh

set -eu

action="$1"
fw_version="${2:-3}"

get_url() {
  fw_info=$(jq "[to_entries.[] | select(.key | startswith(\"$1\"))] | max_by(.key)" updates.json)

  if [ "$fw_info" = "null" ]
  then
    echo "Unknown version $1"
    exit 1
  fi

  fw_hash=$(echo "$fw_info" | jq --raw-output '.value')
  fw_ver=$(echo "$fw_info" | jq --raw-output '.key')
  fw_major=$(echo "$fw_ver" | cut -d '.' -f 1)


  fw_url=""
  if [ "$fw_major" = "3" ]
  then
    fw_url="https://updates-download.cloud.remarkable.engineering/build/reMarkable%20Device/reMarkable2"
  else
    fw_url="https://updates-download.cloud.remarkable.engineering/build/reMarkable%20Device%20Beta/RM110"
  fi

  fw_url="$fw_url/$fw_ver/${fw_ver}_reMarkable2-$fw_hash.signed"
}

download_fw() {
    get_url "$1"

    echo "Downloading $fw_ver from:"
    echo " $fw_url"
    curl -f -o fw.signed "$fw_url"
}


check_fw() {
    get_url "$1"
    echo "Checking $fw_ver at $fw_url"
    curl -f -I "$fw_url"
}

check_all() {
  all_fw=$(jq --raw-output 'keys[]' updates.json)
  for f in $all_fw
  do
    check_fw "$f"
  done
}

case $action in
  download)
    download_fw "$fw_version"
    ;;
  check)
    check_fw "$fw_version"
    ;;
  check-all)
    check_all
    ;;
  *)
    ;;
esac
