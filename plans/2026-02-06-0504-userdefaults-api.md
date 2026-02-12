# Comprehensive UserDefaults API

**Date:** 2026-02-06
**Goal:** Create a full-featured API for accessing, listing, and filtering NSUserDefaults data.

## Overview

Expand the current `/userdefaults` endpoint into a full router with multiple endpoints for comprehensive UserDefaults access.

## API Design

### Router: `/userdefaults`

#### 1. `/userdefaults/` - Index
- Lists all available endpoints

#### 2. `/userdefaults/all` - List All Values
- Returns all key-value pairs from UserDefaults
- Parameters:
  - `suite` (optional): Suite name (default: standard)
  - `filterSystem` (optional): Filter Apple system keys (default: false)
  - `sort` (optional): Sort by key name (asc/desc)

#### 3. `/userdefaults/get` - Get Single Key
- Query a specific key's value
- Parameters:
  - `key` (required): The key to look up
  - `suite` (optional): Suite name

#### 4. `/userdefaults/keys` - List Keys Only
- Returns just the key names (no values)
- Parameters:
  - `suite` (optional): Suite name
  - `filterSystem` (optional): Filter Apple system keys
  - `prefix` (optional): Filter keys starting with prefix
  - `contains` (optional): Filter keys containing substring
  - `sort` (optional): Sort order (asc/desc)

#### 5. `/userdefaults/search` - Search Keys/Values
- Search for keys or values matching a pattern
- Parameters:
  - `query` (required): Search term
  - `searchIn` (optional): "keys", "values", or "both" (default: both)
  - `suite` (optional): Suite name
  - `caseSensitive` (optional): Case-sensitive search (default: false)

#### 6. `/userdefaults/suites` - List Known Suites
- Returns list of known/accessible suites
- Shows: standard, any app group containers, volatile domains

#### 7. `/userdefaults/domains` - List Persistence Domains
- Returns the persistence domain names
- Uses: `persistentDomainNames`

#### 8. `/userdefaults/domain` - Get Domain Contents
- Get contents of a specific persistence domain
- Parameters:
  - `name` (required): Domain name (e.g., bundle identifier)

#### 9. `/userdefaults/volatile` - List Volatile Domains
- Returns volatile domain names
- Uses: `volatileDomainNames`

#### 10. `/userdefaults/types` - Group by Value Type
- Groups keys by their value types (String, Int, Bool, Array, Dictionary, Data, Date)
- Parameters:
  - `suite` (optional): Suite name
  - `filterSystem` (optional): Filter Apple system keys

## Tasks

- [x] Create plans document
- [x] Convert UserDefaultsEndpoints to router pattern (like FilesEndpoints)
- [x] Implement `/` index endpoint
- [x] Implement `/all` endpoint (migrate existing functionality)
- [x] Implement `/get` endpoint for single key lookup
- [x] Implement `/keys` endpoint for key listing
- [x] Implement `/search` endpoint
- [x] Implement `/suites` endpoint
- [x] Implement `/domains` endpoint
- [x] Implement `/domain` endpoint
- [x] Implement `/volatile` endpoint
- [x] Implement `/types` endpoint
- [x] Update server registration to use new router
- [x] Build and test
- [x] Run existing tests (82 tests pass)
- [x] Add new tests for endpoints (20 new tests)

## Implementation Notes

- Use router pattern like FilesEndpoints.createRouter()
- All endpoints run off main thread (runsOnMainThread: false)
- Value serialization should handle all plist types:
  - String, Number (Int/Double), Bool, Date, Data, Array, Dictionary
- Data values should be base64 encoded for JSON compatibility
- Date values should use ISO8601 format
