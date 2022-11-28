# frozen_string_literal: true

class StatusFinder
  attr_reader :url

  def initialize(url)
    @url = url
  end

  def status
    verify_action!

    raise ActiveRecord::RecordNotFound unless TagManager.instance.local_url?(url)

    case recognized_params[:controller]
    when 'statuses'
      status = Status.find(recognized_params[:id])

      status.associated_logs.create(label: "status_finder", data: {
        'recognized_params' => recognized_params,
        'url' => url,
        'caller' => caller
      }.to_json).save!
      status
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  private

  def recognized_params
    Rails.application.routes.recognize_path(url)
  end

  def verify_action!
    unless recognized_params[:action] == 'show'
      raise ActiveRecord::RecordNotFound
    end
  end
end
