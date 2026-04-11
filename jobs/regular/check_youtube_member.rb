# frozen_string_literal: true

# Enqueued immediately after a user connects their YouTube account via the
# "Connect YouTube" OAuth flow (Auth::YouTubeAuthenticator).
# Runs asynchronously so the connect response is not delayed by the API calls.
class Jobs::CheckYoutubeMember < Jobs::Base
  def execute(args)
    user_id = args[:user_id] || args["user_id"]
    return unless user_id

    user = User.find_by(id: user_id)
    return unless user&.active?

    CommunityIntegrations::YoutubeMemberChecker.sync_user(user)
  end
end
