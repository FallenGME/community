# frozen_string_literal: true

# Enqueued immediately after a user authenticates via Twitch OAuth.
# Runs asynchronously so the login response is not delayed by the API call.
class Jobs::CheckTwitchSubscriber < Jobs::Base
  def execute(args)
    user_id = args[:user_id] || args["user_id"]
    return unless user_id

    user = User.find_by(id: user_id)
    return unless user&.active?

    CommunityIntegrations::TwitchChecker.sync_user(user)
  end
end
