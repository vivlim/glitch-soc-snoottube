# frozen_string_literal: true

class ThreadResolveWorker
  include Sidekiq::Worker
  include ExponentialBackoff

  sidekiq_options queue: 'pull', retry: 3

  def perform(child_status_id, parent_url) # discover if there are parent statuses
    child_status  = Status.find(child_status_id)

    parent_status = FetchRemoteStatusService.new.call(parent_url)

    child_status.associated_logs.create(label: "thread_resolve_worker.perform", data: {
      'child_status' => child_status,
      'parent_url' => parent_url,
      'parent_status' => parent_status,
      'caller' => caller
    }.to_json).save!

    return if parent_status.nil?

    child_status.thread = parent_status
    child_status.save!
  rescue ActiveRecord::RecordNotFound
    true
  end
end
