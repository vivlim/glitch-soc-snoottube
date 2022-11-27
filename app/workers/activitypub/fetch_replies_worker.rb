# frozen_string_literal: true

class ActivityPub::FetchRepliesWorker
  include Sidekiq::Worker
  include ExponentialBackoff

  sidekiq_options queue: 'pull', retry: 3

  def perform(parent_status_id, replies_uri)
    parent = Status.find(parent_status_id)
    AssociatedLog.create(status: parent, label: "fetch_replies_worker", data: {
      'parent_status_id' => parent_status_id,
      'replies_uri' => replies_uri
    }.to_json)
    ActivityPub::FetchRepliesService.new.call(parent, replies_uri)
  rescue ActiveRecord::RecordNotFound
    AssociatedLog.create(label: "fetch_replies_worker", data: {
      'parent_status_id' => parent_status_id,
      'replies_uri' => replies_uri
    }.to_json)
    true
  end
end
