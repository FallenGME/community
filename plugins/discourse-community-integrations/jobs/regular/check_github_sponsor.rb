# frozen_string_literal: true

# Enqueued immediately after a user authenticates via GitHub OAuth.
# Runs asynchronously so the login response is not delayed by the GraphQL call.
class Jobs::CheckGithubSponsor < Jobs::Base
  def execute(args)
    user_id = args[:user_id] || args["user_id"]
    return unless user_id

    user = User.find_by(id: user_id)
    return unless user&.active?

    CommunityIntegrations::GithubSponsorsChecker.sync_user(user)
  end
end
