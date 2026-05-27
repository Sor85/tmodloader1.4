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

test_extract_collection_id_from_url
test_extract_collection_id_from_raw_id
test_parse_collection_mod_ids
test_collection_overrides_existing_mod_variables
test_fetches_example_collection_from_steam

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
