# Potential Issues & Mitigations for Admin-Curated Lists

## 🚨 Critical Issues

### 1. Race Conditions

#### **Feed Modification Conflicts**

**Scenario**: Admin adds curated status while user simultaneously adds/removes accounts  
**Impact**: Redis feed inconsistency, duplicate or missing statuses  
**Mitigation**:

```ruby
def add_curated_status_safely(list, status)
  redis.multi do |transaction|
    transaction.zadd(key(:list, list.id), status.id, status.id)
    # Use Redis transactions for atomic operations
  end
end
```

#### **Status Deletion During Curation**

**Scenario**: Status gets deleted while admin is adding it to list  
**Impact**: Orphaned database records, 500 errors  
**Mitigation**: Already handled by `ON DELETE CASCADE` in schema

### 2. Web UI Breaking Changes

#### **Redux Store Staleness**

**Scenario**: Admin adds status, user's timeline doesn't update  
**Current Code**: `app/javascript/mastodon/actions/streaming.js` only handles specific events  
**Impact**: User confusion, requires manual refresh  
**Mitigation**:

```javascript
// Need to add to streaming/index.js
case 'list.update':
  // Trigger timeline refresh for affected list
  dispatch(refreshTimeline(`list:${payload.list_id}`));
  break;
```

#### **List Edit Modal Breakage**

**Files at risk**:

- `app/javascript/mastodon/features/lists/components/list_editor.jsx`
- `app/javascript/mastodon/features/list_editor/index.jsx`

**Mitigation**: Add `editable` field to REST::ListSerializer:

```ruby
class REST::ListSerializer < ActiveModel::Serializer
  attributes :id, :title, :replies_policy, :exclusive, :editable  # NEW

  def editable
    object.editable_by_owner || object.curated_by_id.nil?
  end
end
```

### 3. Third-Party App Compatibility

#### **Ivory/Toot!/Metatext Cache Inconsistency**

**Issue**: Apps cache list->account relationships, won't show curated statuses correctly  
**Impact**: Curated statuses appear to be from "nobody" or might not appear  
**Mitigation**: Can't fully fix, but ensure `/api/v1/timelines/list/:id` returns valid status JSON

#### **Bulk Operations Failing**

**Apps affected**: Any that do bulk list management (Tweetbot heritage apps)  
**Mitigation**: Consistent 403 responses:

```ruby
before_action :check_list_editable!, only: [:update, :destroy]

def check_list_editable!
  return if @list.editable_by?(current_account)
  render json: { error: 'This list is managed by administrators' }, status: 403
end
```

### 4. Performance Regressions

#### **Feed Regeneration Timeout**

**Scenario**: Converting large list to curated with 1000+ statuses  
**Impact**: Request timeout, partial feed  
**Mitigation**:

```ruby
class CurateListWorker
  def perform(list_id, status_ids)
    status_ids.each_slice(100) do |batch|
      # Process in batches
      sleep 0.1  # Prevent Redis overload
    end
  end
end
```

#### **N+1 Query on List Index**

**Current code**: Lists controller doesn't eager load curated_by  
**Mitigation**:

```ruby
def index
  @lists = List.where(account: current_account)
               .includes(:curator)  # Add this
               .all
end
```

### 5. Security/Privacy Violations

#### **Private Status Leakage**

**Scenario**: Admin adds private status to user's list that user can't normally see  
**Impact**: Privacy violation, potential legal issue  
**Critical Mitigation**:

```ruby
def add_status
  @status = Status.find(params[:status_id])

  # CRITICAL: Check visibility
  unless @status.distributable? ||
         @list.account.following?(@status.account) ||
         @status.account_id == @list.account_id
    render json: { error: 'Status not visible to list owner' }, status: 403
    return
  end

  # ... rest of method
end
```

#### **Bypassing Blocks/Mutes**

**Scenario**: Curated status from account user has blocked  
**Impact**: User harassment, trust violation  
**Mitigation**:

```ruby
# In FeedManager
def filter_from_list?(status, list)
  return true if list.account.blocking?(status.account_id)
  return true if list.account.muting?(status.account_id)
  # ... existing filters
end
```

### 6. Data Integrity Problems

#### **Orphaned Redis Entries**

**Scenario**: Database rollback but Redis already modified  
**Impact**: Ghost statuses in timeline  
**Mitigation**:

```ruby
class CuratedListStatus < ApplicationRecord
  after_commit :add_to_feed, on: :create  # Use after_commit, not after_create
  after_commit :remove_from_feed, on: :destroy
end
```

#### **List Count Limit Bypass**

**Current code**: `PER_ACCOUNT_LIMIT = 50` in List model  
**Issue**: Admin-created lists could exceed user's limit  
**Mitigation**:

```ruby
def validate_account_lists_limit
  return if curated_by_id.present?  # Skip validation for curated lists
  errors.add(:base, I18n.t('lists.errors.limit')) if account.owned_lists.user_created.count >= PER_ACCOUNT_LIMIT
end
```

### 7. User Experience Degradation

#### **Timeline Chronology Breaks**

**Scenario**: Old curated statuses appear at top of timeline  
**Impact**: Confusing timeline order  
**Mitigation**: Honor original timestamps:

```ruby
def push_curated_status_to_list(list, status)
  # Use status's actual timestamp, not current time
  redis.zadd(key(:list, list.id), status.id, status.id)
end
```

#### **Notification Spam**

**Scenario**: Adding many curated statuses triggers streaming updates  
**Impact**: User gets bombarded with updates  
**Mitigation**: Use notification preferences:

```ruby
def add_curated_status(list, status)
  # Check notification preferences
  if list.silent_updates || !list.notify_on_updates
    # Add silently
    FeedManager.instance.add_to_feed(:list, list.id, status)
  else
    # Add with notification
    FeedManager.instance.push_to_list(list, status)
  end
end
```

### 8. User Control & Opt-out

#### **Soft Delete Benefits**

- User can "delete" (opt-out) without losing admin's curation work
- Admin sees user has opted out and stops adding content
- User can restore the list later if they change their mind
- No data loss, just visibility control

#### **Implementation**

```ruby
# Check before any admin operations
def can_curate?(list)
  list.curated? && list.user_deleted_at.nil?
end
```

## Testing Checklist

### Critical Test Cases

- [ ] User deletes account with curated lists - verify cleanup
- [ ] Admin adds deleted status - verify error handling
- [ ] List with 10k+ curated statuses - verify performance
- [ ] Concurrent admin + user modifications - verify consistency
- [ ] Private status visibility checks - verify no leakage
- [ ] Block/mute filter application - verify filtering works
- [ ] Third-party app timeline fetch - verify compatibility
- [ ] Web UI list management - verify no JS errors
- [ ] Streaming updates - verify real-time updates work
- [ ] Database rollback - verify Redis consistency

## Rollback Plan

1. **Feature flag first**: Add `ENV['ENABLE_CURATED_LISTS']` check
2. **Gradual rollout**: Start with admin accounts only
3. **Quick disable**: Can set `curated_by_id = NULL` to convert back to normal lists
4. **Redis cleanup**: Script to remove curated statuses from feeds if needed

## Monitoring Requirements

- Alert on: 403 errors on list endpoints > 100/hour
- Alert on: CuratedListStatus creation failures
- Dashboard: Number of curated lists, statuses per list
- Performance: p99 latency for `/api/v1/timelines/list/:id`
