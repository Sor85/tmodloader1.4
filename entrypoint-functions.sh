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

# Converts a newline-separated list of Workshop IDs into a comma-separated list.
function join_mod_ids () {
  tr '\n' ',' | sed 's/,$//'
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
