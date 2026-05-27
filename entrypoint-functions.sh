#!/bin/bash

# Shared startup helpers for resolving, downloading, and enabling Steam Workshop mods.

# Extracts the numeric collection ID from a Steam Workshop collection URL or raw ID.
function extract_collection_id () {
  local collectionId
  collectionId=$(echo "$1" | sed -n 's/.*[?&]id=\([0-9][0-9]*\).*/\1/p')
  if test -n "$collectionId" ; then
    echo "$collectionId"
    return
  fi

  echo "$1" | sed -n 's/^\([0-9][0-9]*\)$/\1/p'
}

# Prints child Workshop item IDs from a Steam collection details response.
function parse_collection_mod_ids () {
  if test "$#" -gt 0 ; then
    echo "$1"
  else
    cat
  fi | sed 's/"children"/\
"children"/g' \
    | sed -n '/"children"/,$p' \
    | grep -o '"publishedfileid":"[0-9][0-9]*"' \
    | sed 's/[^0-9]//g'
}

# Fetches collection details from Steam's public collection API.
function fetch_collection_details () {
  local postData
  local url
  postData="collectioncount=1&publishedfileids[0]=$1"
  url="https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"

  if command -v wget >/dev/null 2>&1 ; then
    wget -qO- --post-data="$postData" "$url"
    return
  fi

  if command -v curl >/dev/null 2>&1 ; then
    curl -s -X POST "$url" -d "$postData"
    return
  fi

  echo -e "[!!] FATAL: wget or curl is required to resolve TMOD_MOD_COLLECTION."
  return 1
}

# Fetches published file details from Steam's public Workshop item API.
function fetch_published_file_details () {
  local itemCount
  local postData
  local url
  itemCount=$(echo "$1" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' ')
  postData="itemcount=$itemCount"
  url="https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

  local index
  index=0
  echo "$1" | tr ',' '\n' | sed '/^$/d' | while read modId
  do
    echo "publishedfileids[$index]=$modId"
    index=$((index + 1))
  done | while read field
  do
    postData="$postData&$field"
    echo "$postData"
  done | tail -n 1 | while read builtPostData
  do
    if command -v wget >/dev/null 2>&1 ; then
      wget -qO- --post-data="$builtPostData" "$url"
      return
    fi

    if command -v curl >/dev/null 2>&1 ; then
      curl -s -X POST "$url" -d "$builtPostData"
      return
    fi

    echo -e "[!!] FATAL: wget or curl is required to check Workshop mod updates."
    return 1
  done
}

# Prints Workshop item IDs and their Steam update timestamps.
function parse_published_file_update_times () {
  if test "$#" -gt 0 ; then
    echo "$1"
  else
    cat
  fi | tr '{' '\n' \
    | grep '"publishedfileid":"[0-9][0-9]*"' \
    | grep '"time_updated":[0-9][0-9]*' \
    | sed -n 's/.*"publishedfileid":"\([0-9][0-9]*\)".*"time_updated":\([0-9][0-9]*\).*/\1 \2/p'
}

# Converts a newline-separated list of Workshop IDs into a comma-separated list.
function join_mod_ids () {
  tr '\n' ',' | sed 's/,$//'
}

# Counts non-empty IDs in a comma-separated Workshop ID list.
function count_mod_ids () {
  echo "$1" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' '
}

# Prints the recorded update timestamp for a Workshop item.
function get_recorded_update_time () {
  if test ! -f "$2" ; then
    return
  fi

  awk -v modId="$1" '$1 == modId { print $2; exit }' "$2"
}

# Checks whether a Workshop item exists in the local Steam workshop cache.
function mod_cache_exists () {
  test -d "$2/$1"
}

# Returns a comma-separated list of missing or updated Workshop IDs.
function filter_download_mod_ids () {
  local modIds
  local stateFile
  local contentPath
  local updateTimes
  modIds="$1"
  stateFile="$2"
  contentPath="$3"

  updateTimes=$(fetch_published_file_details "$modIds" | parse_published_file_update_times)
  if test -z "$updateTimes" || test "$(echo "$updateTimes" | wc -l | tr -d ' ')" -lt "$(count_mod_ids "$modIds")" ; then
    echo "$modIds"
    return
  fi

  echo "$updateTimes" | while read modId updateTime
  do
    local recordedTime
    recordedTime=$(get_recorded_update_time "$modId" "$stateFile")

    if ! mod_cache_exists "$modId" "$contentPath" || test -z "$recordedTime" || test "$updateTime" -gt "$recordedTime" ; then
      echo "$modId"
    fi
  done | join_mod_ids
}

# Persists current Steam update timestamps for Workshop IDs.
function write_mod_update_state () {
  local modIds
  local stateFile
  local temporaryStateFile
  modIds="$1"
  stateFile="$2"

  mkdir -p "$(dirname "$stateFile")"
  temporaryStateFile=$(mktemp)
  fetch_published_file_details "$modIds" | parse_published_file_update_times > "$temporaryStateFile"

  if test -s "$temporaryStateFile" ; then
    mv "$temporaryStateFile" "$stateFile"
  else
    rm -f "$temporaryStateFile"
  fi
}

# Applies TMOD_MOD_COLLECTION precedence by populating download and enable mod lists.
function set_mod_sources () {
  if test -z "${TMOD_MOD_COLLECTION:-}" ; then
    return
  fi

  echo -e "[SYSTEM] TMOD_MOD_COLLECTION is set. Ignoring TMOD_AUTODOWNLOAD and TMOD_ENABLEDMODS."

  local collectionId
  collectionId=$(extract_collection_id "$TMOD_MOD_COLLECTION")
  if test -z "$collectionId" ; then
    echo -e "[!!] FATAL: TMOD_MOD_COLLECTION must be a Steam Workshop collection URL or collection ID."
    exit 1
  fi

  echo -e "[SYSTEM] Resolving Steam Workshop collection $collectionId..."

  local response
  response=$(fetch_collection_details "$collectionId")

  local modIds
  modIds=$(parse_collection_mod_ids "$response" | join_mod_ids)
  if test -z "$modIds" ; then
    echo -e "[!!] FATAL: No mods were found in Steam Workshop collection $collectionId."
    exit 1
  fi

  TMOD_AUTODOWNLOAD="$modIds"
  TMOD_ENABLEDMODS="$modIds"
  echo -e "[SYSTEM] Resolved Steam Workshop collection $collectionId to: $modIds"
}
