# Admin-Curated Lists Implementation Plan

## Overview

Extend Mastodon's existing list functionality to allow administrators to create and curate lists on behalf of users, while maintaining full backwards compatibility with the Mastodon API and third-party clients.

## Core Design Principles

- **100% backwards compatible** - No breaking changes to existing APIs
- **Transparent to clients** - Third-party apps see no difference
- **Mixed content support** - Lists can contain both followed accounts and individually curated statuses
- **User visibility** - Curated lists appear as normal lists to users

## Database Schema Changes

### 1. Modify `lists` table

```sql
ALTER TABLE lists
ADD COLUMN curated_by_id bigint DEFAULT NULL,
ADD COLUMN editable_by_owner boolean DEFAULT true,
ADD COLUMN user_deleted_at timestamp DEFAULT NULL,  -- Soft delete by user
ADD COLUMN notify_on_updates boolean DEFAULT true,  -- User notification preference
ADD COLUMN silent_updates boolean DEFAULT false,    -- Admin can choose silent mode
ADD FOREIGN KEY (curated_by_id) REFERENCES accounts(id);

-- NULL curated_by_id = normal user-created list
-- Non-NULL curated_by_id = admin-curated list
-- Non-NULL user_deleted_at = user has opted out of curated list
```

### 2. Create `curated_list_statuses` table

```sql
CREATE TABLE curated_list_statuses (
  id bigserial PRIMARY KEY,
  list_id bigint NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  status_id bigint NOT NULL REFERENCES statuses(id) ON DELETE CASCADE,
  added_by_id bigint NOT NULL REFERENCES accounts(id),
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL,
  UNIQUE(list_id, status_id)
);

CREATE INDEX idx_curated_list_statuses_list_id ON curated_list_statuses(list_id);
CREATE INDEX idx_curated_list_statuses_status_id ON curated_list_statuses(status_id);
```

## Code Implementation

### 1. Model Changes

#### app/models/list.rb

```ruby
class List < ApplicationRecord
  # Existing associations
  belongs_to :account
  has_many :list_accounts, inverse_of: :list, dependent: :destroy
  has_many :accounts, through: :list_accounts

  # New associations
  belongs_to :curator, class_name: 'Account', foreign_key: 'curated_by_id', optional: true
  has_many :curated_list_statuses, dependent: :destroy
  has_many :curated_statuses, through: :curated_list_statuses, source: :status

  # New scopes
  scope :curated, -> { where.not(curated_by_id: nil) }
  scope :user_created, -> { where(curated_by_id: nil) }

  # New methods
  def curated?
    curated_by_id.present?
  end

  def editable_by?(account)
    return false if account.nil?
    return true if account.id == account_id && editable_by_owner
    return true if account.id == curated_by_id
    false
  end
end
```

#### app/models/curated_list_status.rb (new)

```ruby
class CuratedListStatus < ApplicationRecord
  belongs_to :list
  belongs_to :status
  belongs_to :added_by, class_name: 'Account'

  validates :status_id, uniqueness: { scope: :list_id }

  after_create :add_to_feed
  after_destroy :remove_from_feed

  private

  def add_to_feed
    FeedManager.instance.push_to_list(list, status)
  end

  def remove_from_feed
    FeedManager.instance.unpush_from_list(list, status)
  end
end
```

### 2. FeedManager Modifications

#### app/lib/feed_manager.rb

```ruby
class FeedManager
  # New method for pushing curated statuses
  def push_curated_status_to_list(list, status)
    return false unless add_to_feed(:list, list.id, status, aggregate_reblogs: list.account.user&.aggregates_reblogs?)
    trim(:list, list.id)
    PushUpdateWorker.perform_async(list.account_id, status.id, "timeline:list:#{list.id}")
    true
  end

  # Modified merge_into_list to include curated statuses
  def merge_into_list(from_account, list)
    # Existing account-based merge logic...

    # Add curated statuses if any
    if list.curated?
      list.curated_statuses.find_each do |status|
        add_to_feed(:list, list.id, status, aggregate_reblogs: list.account.user&.aggregates_reblogs?)
      end
    end
  end
end
```

### 3. Admin Controllers

#### app/controllers/admin/curated_lists_controller.rb (new)

```ruby
class Admin::CuratedListsController < Admin::BaseController
  before_action :set_account, only: [:new, :create]
  before_action :set_list, except: [:index, :new, :create]

  def index
    @lists = List.curated.includes(:account, :curator).page(params[:page])
  end

  def new
    @list = @account.lists.build
  end

  def create
    @list = @account.lists.build(list_params)
    @list.curated_by = current_account

    if @list.save
      redirect_to admin_curated_list_path(@list), notice: 'List created successfully'
    else
      render :new
    end
  end

  def add_status
    @status = Status.find(params[:status_id])

    @curated_status = @list.curated_list_statuses.build(
      status: @status,
      added_by: current_account
    )

    if @curated_status.save
      render json: { success: true }
    else
      render json: { error: @curated_status.errors.full_messages }, status: 422
    end
  end

  def remove_status
    @curated_status = @list.curated_list_statuses.find_by!(status_id: params[:status_id])
    @curated_status.destroy
    render json: { success: true }
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_list
    @list = List.find(params[:id])
  end

  def list_params
    params.require(:list).permit(:title, :replies_policy, :editable_by_owner)
  end
end
```

### 4. API Endpoints (Admin only)

#### config/routes/admin.rb

```ruby
namespace :admin do
  resources :curated_lists do
    member do
      post 'statuses/:status_id', to: 'curated_lists#add_status', as: :add_status
      delete 'statuses/:status_id', to: 'curated_lists#remove_status', as: :remove_status
    end
  end
end
```

### 5. User-facing Modifications

#### app/controllers/api/v1/lists_controller.rb

```ruby
class Api::V1::ListsController < Api::BaseController
  # Modified index to exclude soft-deleted curated lists
  def index
    @lists = List.where(account: current_account)
                 .where(user_deleted_at: nil)
                 .all
    render json: @lists, each_serializer: REST::ListSerializer
  end

  # Modified update action to respect curation
  def update
    if @list.curated? && !@list.editable_by_owner
      # Allow updating notification preferences
      @list.update!(notify_on_updates: params[:notify_on_updates]) if params.key?(:notify_on_updates)
      render json: @list, serializer: REST::ListSerializer
    else
      @list.update!(list_params)
      render json: @list, serializer: REST::ListSerializer
    end
  end

  # Modified destroy - soft delete for curated lists
  def destroy
    if @list.curated?
      # Soft delete - user opting out
      @list.update!(user_deleted_at: Time.current)
      FeedManager.instance.clean_feeds!(:list, [@list.id])
    else
      # Hard delete for user-created lists
      @list.destroy!
    end
    render_empty
  end
end
```

## Migration Steps

1. Deploy database migrations
2. Deploy code changes
3. Create admin UI views
4. Test with a small subset of users
5. Roll out to production

## Backwards Compatibility Guarantees

1. **API Response Format**: No changes to REST::ListSerializer output
2. **Timeline Endpoints**: /api/v1/timelines/list/:id continues to work identically
3. **List Management**: Users can still create/manage their own lists
4. **Streaming API**: No changes to WebSocket event format
5. **Federation**: Lists remain local-only, no ActivityPub impact

## Security Considerations

1. Admin actions are logged in the admin action log
2. Rate limiting on admin API endpoints
3. Curated lists clearly marked in user interface
4. Users cannot delete admin-curated lists (unless editable_by_owner is true)

## Testing Strategy

1. Unit tests for new models and methods
2. Integration tests for admin workflows
3. API compatibility tests with third-party clients
4. Performance tests for large curated lists
5. Edge case testing for mixed content lists
