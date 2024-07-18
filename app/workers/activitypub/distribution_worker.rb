# frozen_string_literal: true

class ActivityPub::DistributionWorker < ActivityPub::RawDistributionWorker
  # Distribute a new status or an edit of a status to all the places
  # where the status is supposed to go or where it was interacted with
  def perform(status_id)
    @status  = Status.find(status_id)
    @account = @status.account

    if @status.not_federated_visibility?
      distribute_locally!
    else
      distribute!
    end

  rescue ActiveRecord::RecordNotFound
    true
  end

  protected

  def distribute_locally!
    inboxes = local_inboxes
    inboxes.each do |inbox|
      send_to_inbox(inbox, payload)
    end
  end

  def local_inboxes
    @local_inboxes ||= StatusReachFinder.new(@status).local_inboxes
  end

  def inboxes
    @inboxes ||= StatusReachFinder.new(@status).inboxes
  end

  def payload
    @payload ||= Oj.dump(serialize_payload(activity, ActivityPub::ActivitySerializer, signer: @account))
  end

  def activity
    ActivityPub::ActivityPresenter.from_status(@status)
  end

  def options
    { 'synchronize_followers' => @status.private_visibility? }
  end
end
