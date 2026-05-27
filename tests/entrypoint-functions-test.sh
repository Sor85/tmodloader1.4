#!/bin/bash

set -u

repoRoot=$(cd "$(dirname "$0")/.." && pwd)
source "$repoRoot/entrypoint-functions.sh"

failures=0

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $message"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failures=$((failures + 1))
  fi
}

test_extract_collection_id_from_url() {
  local id
  id=$(extract_collection_id "https://steamcommunity.com/sharedfiles/filedetails/?id=3732144707")
  assert_equals "3732144707" "$id" "extracts collection ID from Steam URL"
}

test_extract_collection_id_from_raw_id() {
  local id
  id=$(extract_collection_id "3732144707")
  assert_equals "3732144707" "$id" "accepts raw collection ID"
}

test_parse_collection_mod_ids() {
  local json
  local ids

  json='{"response":{"collectiondetails":[{"publishedfileid":"3732144707","children":[{"publishedfileid":"3449156562"},{"publishedfileid":"2815010161"}]}]}}'
  ids=$(parse_collection_mod_ids "$json")

  assert_equals $'3449156562\n2815010161' "$ids" "parses child mod IDs from collection response"
}

test_collection_overrides_existing_mod_variables() {
  fetch_collection_details() {
    echo '{"response":{"collectiondetails":[{"publishedfileid":"3732144707","children":[{"publishedfileid":"3449156562"},{"publishedfileid":"2815010161"}]}]}}'
  }

  TMOD_MOD_COLLECTION="https://steamcommunity.com/sharedfiles/filedetails/?id=3732144707"
  TMOD_AUTODOWNLOAD="111"
  TMOD_ENABLEDMODS="222"

  set_mod_sources

  assert_equals "3449156562,2815010161" "$TMOD_AUTODOWNLOAD" "collection sets mods to download"
  assert_equals "3449156562,2815010161" "$TMOD_ENABLEDMODS" "collection sets mods to enable"

  unset -f fetch_collection_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_fetches_example_collection_from_steam() {
  local ids

  ids=$(fetch_collection_details "3732144707" | parse_collection_mod_ids | join_mod_ids)

  if [[ "$ids" != *"3449156562"* ]]; then
    echo "FAIL: fetches and parses the example Steam collection"
    echo "  expected list to contain: 3449156562"
    echo "  actual: $ids"
    failures=$((failures + 1))
  fi
}

test_parse_published_file_update_times() {
  local json
  local updateTimes

  json='{"response":{"publishedfiledetails":[{"publishedfileid":"3449156562","time_updated":1775122401},{"publishedfileid":"2815010161","time_updated":1720581189}]}}'
  updateTimes=$(parse_published_file_update_times "$json")

  assert_equals $'3449156562 1775122401\n2815010161 1720581189' "$updateTimes" "parses update times from published file response"
}

test_filter_download_mod_ids_selects_missing_and_updated_mods() {
  local contentPath
  local stateFile
  local ids

  contentPath=$(mktemp -d)
  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
2815010161 1720000000
STATE
  mkdir -p "$contentPath/3449156562" "$contentPath/2815010161"

  fetch_published_file_details() {
    echo '{"response":{"publishedfiledetails":[{"publishedfileid":"3449156562","time_updated":1775122401},{"publishedfileid":"2815010161","time_updated":1720581189},{"publishedfileid":"2992213994","time_updated":1700000000}]}}'
  }

  ids=$(filter_download_mod_ids "3449156562,2815010161,2992213994" "$stateFile" "$contentPath")

  assert_equals "2815010161,2992213994" "$ids" "selects only missing or updated mods"

  rm -rf "$contentPath"
  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_filter_download_mod_ids_selects_missing_local_mod() {
  local contentPath
  local stateFile
  local ids

  contentPath=$(mktemp -d)
  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
2815010161 1720581189
STATE
  mkdir -p "$contentPath/3449156562"

  fetch_published_file_details() {
    echo '{"response":{"publishedfiledetails":[{"publishedfileid":"3449156562","time_updated":1775122401},{"publishedfileid":"2815010161","time_updated":1720581189}]}}'
  }

  ids=$(filter_download_mod_ids "3449156562,2815010161" "$stateFile" "$contentPath")

  assert_equals "2815010161" "$ids" "selects mods missing from local Workshop cache"

  rm -rf "$contentPath"
  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_filter_download_mod_ids_returns_empty_when_all_current() {
  local contentPath
  local stateFile
  local ids

  contentPath=$(mktemp -d)
  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
2815010161 1720581189
STATE
  mkdir -p "$contentPath/3449156562" "$contentPath/2815010161"

  fetch_published_file_details() {
    echo '{"response":{"publishedfiledetails":[{"publishedfileid":"3449156562","time_updated":1775122401},{"publishedfileid":"2815010161","time_updated":1720581189}]}}'
  }

  ids=$(filter_download_mod_ids "3449156562,2815010161" "$stateFile" "$contentPath")

  assert_equals "" "$ids" "skips download when all mods are current"

  rm -rf "$contentPath"
  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_filter_download_mod_ids_downloads_all_when_update_check_fails() {
  local contentPath
  local stateFile
  local ids

  contentPath=$(mktemp -d)
  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
2815010161 1720581189
STATE
  mkdir -p "$contentPath/3449156562" "$contentPath/2815010161"

  fetch_published_file_details() {
    return 1
  }

  ids=$(filter_download_mod_ids "3449156562,2815010161" "$stateFile" "$contentPath")

  assert_equals "3449156562,2815010161" "$ids" "downloads all mods when update metadata cannot be checked"

  rm -rf "$contentPath"
  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_filter_download_mod_ids_downloads_all_when_update_check_is_partial() {
  local contentPath
  local stateFile
  local ids

  contentPath=$(mktemp -d)
  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
2815010161 1720581189
STATE
  mkdir -p "$contentPath/3449156562" "$contentPath/2815010161"

  fetch_published_file_details() {
    echo '{"response":{"publishedfiledetails":[{"publishedfileid":"3449156562","time_updated":1775122401}]}}'
  }

  ids=$(filter_download_mod_ids "3449156562,2815010161" "$stateFile" "$contentPath")

  assert_equals "3449156562,2815010161" "$ids" "downloads all mods when update metadata is incomplete"

  rm -rf "$contentPath"
  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_write_mod_update_state_persists_current_times() {
  local stateFile
  local state

  stateFile=$(mktemp)

  fetch_published_file_details() {
    echo '{"response":{"publishedfiledetails":[{"publishedfileid":"2815010161","time_updated":1720581189},{"publishedfileid":"2992213994","time_updated":1700000000}]}}'
  }

  write_mod_update_state "2815010161,2992213994" "$stateFile"
  state=$(cat "$stateFile")

  assert_equals $'2815010161 1720581189\n2992213994 1700000000' "$state" "persists current update times"

  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_write_mod_update_state_keeps_existing_state_when_update_check_fails() {
  local stateFile
  local state

  stateFile=$(mktemp)
  cat > "$stateFile" <<STATE
3449156562 1775122401
STATE

  fetch_published_file_details() {
    return 1
  }

  write_mod_update_state "3449156562" "$stateFile"
  state=$(cat "$stateFile")

  assert_equals "3449156562 1775122401" "$state" "keeps existing state when update metadata cannot be checked"

  rm -f "$stateFile"
  unset -f fetch_published_file_details
  source "$repoRoot/entrypoint-functions.sh"
}

test_extract_collection_id_from_url
test_extract_collection_id_from_raw_id
test_parse_collection_mod_ids
test_collection_overrides_existing_mod_variables
test_fetches_example_collection_from_steam
test_parse_published_file_update_times
test_filter_download_mod_ids_selects_missing_and_updated_mods
test_filter_download_mod_ids_selects_missing_local_mod
test_filter_download_mod_ids_returns_empty_when_all_current
test_filter_download_mod_ids_downloads_all_when_update_check_fails
test_filter_download_mod_ids_downloads_all_when_update_check_is_partial
test_write_mod_update_state_persists_current_times
test_write_mod_update_state_keeps_existing_state_when_update_check_fails

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
