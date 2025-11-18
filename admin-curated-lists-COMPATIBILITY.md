# Third-Party App Compatibility Strategy

## Critical API Contracts to Maintain

### 1. List Management Endpoints

#### GET /api/v1/lists

**Current Response:**

```json
[
  {
    "id": "12345",
    "title": "Friends",
    "replies_policy": "list",
    "exclusive": false
  }
]
```

**Our Response (MUST be identical):**

```json
[
  {
    "id": "12345",
    "title": "Weekly Highlights", // Can be different title
    "replies_policy": "list",
    "exclusive": false
    // NO new fields here - would break strict parsers
  }
]
```

#### DELETE /api/v1/lists/:id

**Critical**: Must return 200 OK, not 403

```ruby
def destroy
  if @list.curated?
    # DON'T return 403 - apps won't understand
    @list.update!(user_deleted_at: Time.current)
    # Return same empty response as normal delete
    render_empty  # Returns 200 OK with empty body
  else
    @list.destroy!
    render_empty
  end
end
```

### 2. Timeline Endpoint - Most Critical

#### GET /api/v1/timelines/list/:list_id

**Must return standard Status objects:**

```json
{
  "id": "103254962155278888",
  "created_at": "2019-11-26T23:27:31.000Z",
  "in_reply_to_id": null,
  "account": {
    "id": "1",
    "username": "alice"
    // Standard account object
  },
  "content": "<p>Hello world</p>"
  // ... standard status fields
}
```

**Critical Requirements:**

1. ✅ Status must have valid `account` object (not null)
2. ✅ All standard fields must be present
3. ✅ No new fields that could confuse parsers
4. ✅ Pagination headers must work correctly

### 3. List Accounts Endpoint

#### GET /api/v1/lists/:id/accounts

**Problem**: Curated statuses aren't from accounts in the list!

**Solution**: Return accounts whose statuses are in the list

```ruby
def show
  if @list.curated?
    # Return unique accounts from curated statuses + list accounts
    account_ids = @list.accounts.pluck(:id)
    curated_account_ids = @list.curated_statuses.pluck(:account_id).uniq
    all_account_ids = (account_ids + curated_account_ids).uniq

    @accounts = Account.where(id: all_account_ids)
                      .without_suspended
                      .includes(:account_stat, :user)
  else
    # Normal behavior
    @accounts = @list.accounts.without_suspended.includes(:account_stat, :user)
  end

  render json: @accounts, each_serializer: REST::AccountSerializer
end
```

## Compatibility Testing Matrix

### Apps to Test

| App           | Platform | Critical Features                          | Test Priority |
| ------------- | -------- | ------------------------------------------ | ------------- |
| **Ivory**     | iOS/Mac  | Aggressive caching, custom list management | HIGH          |
| **Ice Cubes** | iOS      | SwiftUI, modern API usage                  | HIGH          |
| **Toot!**     | iOS      | Oldest, strict API compliance              | HIGH          |
| **Tusky**     | Android  | Reference implementation                   | HIGH          |
| **Elk**       | Web      | Progressive web app                        | MEDIUM        |
| **Phanpy**    | Web      | Modern web client                          | MEDIUM        |
| **Mammoth**   | iOS/Mac  | Newer, may be flexible                     | LOW           |

### Test Cases for Each App

```ruby
# Test harness for API compatibility
class ThirdPartyCompatibilityTest
  def test_list_operations(app_name)
    # 1. Create curated list for test user
    list = create_curated_list(user)

    # 2. Test: GET /api/v1/lists
    response = api_get("/api/v1/lists", user_token)
    assert response.includes?(list)
    assert response[list].keys == ["id", "title", "replies_policy", "exclusive"]

    # 3. Test: GET /api/v1/timelines/list/:id
    add_curated_status(list, status)
    response = api_get("/api/v1/timelines/list/#{list.id}", user_token)
    assert response.first["account"].present?
    assert response.first["content"].present?

    # 4. Test: DELETE /api/v1/lists/:id
    response = api_delete("/api/v1/lists/#{list.id}", user_token)
    assert response.status == 200
    assert response.body.empty?

    # 5. Verify list is hidden but not destroyed
    assert List.find(list.id).user_deleted_at.present?
  end
end
```

## Potential Breaking Points & Mitigations

### 1. **Ivory's Smart Lists**

**Issue**: Caches account->list relationships, won't show curated statuses
**Mitigation**:

```ruby
# Force cache invalidation via ETag changes
def show
  @accounts = load_accounts
  # Include curated status count in ETag
  fresh_when(@accounts, last_modified: @list.updated_at)
end
```

### 2. **Toot!'s List Editor**

**Issue**: Expects to manage all list accounts, will be confused by curated statuses
**Mitigation**:

```ruby
# Make curated lists appear read-only
class REST::ListSerializer < ActiveModel::Serializer
  attributes :id, :title, :replies_policy, :exclusive

  # DON'T add new attributes - but we can modify behavior
  def title
    if object.curated? && !object.editable_by_owner
      "#{object.title} [Curated]"  # Visual indicator
    else
      object.title
    end
  end
end
```

### 3. **Tusky's List Timeline**

**Issue**: May show "via @unknown" for curated statuses
**Mitigation**: Ensure all statuses have valid account associations (already handled by our design)

## API Version Strategy

### Option 1: Stealth Compatibility (Recommended)

- No version changes
- Curated lists work identically to normal lists from API perspective
- Apps never know the difference

### Option 2: Feature Detection

```ruby
# Add to /api/v2/instance
{
  "configuration": {
    "lists": {
      "max_lists": 50,
      "curated_lists": true  // New capability flag
    }
  }
}
```

### Option 3: New Endpoints (Not Recommended)

- Would require app updates
- Breaks compatibility goal

## Implementation Checklist

### Pre-Launch Testing

- [ ] **Ivory**: Test list creation, timeline viewing, deletion
- [ ] **Ice Cubes**: Test timeline refresh, pagination
- [ ] **Toot!**: Test list management, account addition/removal
- [ ] **Tusky**: Full CRUD operations on lists
- [ ] **Web**: Ensure React UI handles all cases

### API Behavior Guarantees

1. **No New Required Fields** in existing endpoints
2. **Same HTTP Status Codes** (200, 404, 422)
3. **Same Pagination** headers (Link, X-Total-Count)
4. **Same Rate Limits** apply
5. **Same OAuth Scopes** required

### Monitoring for Compatibility

```ruby
# Log third-party app usage patterns
class Api::BaseController
  after_action :log_app_compatibility

  def log_app_compatibility
    if doorkeeper_token&.application
      CompatibilityLog.create!(
        app_name: doorkeeper_token.application.name,
        endpoint: request.path,
        status: response.status,
        user_agent: request.user_agent
      )
    end
  end
end
```

## Rollback Plan if Apps Break

### Immediate Mitigation

```ruby
# Feature flag to disable curated lists per-app
class Api::V1::ListsController
  def index
    if incompatible_app?
      # Return only non-curated lists
      @lists = List.where(account: current_account, curated_by_id: nil)
    else
      # Normal behavior including curated
      @lists = List.where(account: current_account).where(user_deleted_at: nil)
    end
  end

  private

  def incompatible_app?
    # Maintain a list of known incompatible apps
    %w[Ivory/1.0 Toot!/2.0].any? { |app| request.user_agent&.include?(app) }
  end
end
```

### Emergency Revert

```sql
-- Quick disable of all curated lists
UPDATE lists SET user_deleted_at = NOW() WHERE curated_by_id IS NOT NULL;
```

## Summary

**To ensure compatibility:**

1. **Never add fields** to existing API responses
2. **Always return 200 OK** for successful operations (even soft deletes)
3. **Include curated accounts** in `/api/v1/lists/:id/accounts`
4. **Test with real apps** before launch
5. **Monitor API usage** patterns post-launch
6. **Have rollback ready** for incompatible apps

The key is that curated lists must be **indistinguishable** from normal lists at the API level. The only difference is their content source, not their structure or behavior.
