# frozen_string_literal: true

module CommunityIntegrations
  # Checks whether a Discourse user is actively sponsoring the configured
  # GitHub account and syncs their group membership accordingly.
  #
  # API used:
  #   GitHub GraphQL endpoint — https://api.github.com/graphql
  #
  #   Query: viewer { sponsorshipsAsMaintainer } is NOT what we want.
  #   Instead we query the sponsorable user's `viewerIsSponsoring` field,
  #   which returns true when the *authenticated viewer* sponsors that user.
  #
  # Authentication:
  #   The user's GitHub OAuth access token (stored in UserAssociatedAccount).
  #   GitHub tokens do not expire unless manually revoked, so no refresh logic
  #   is needed — the stored token is used as-is.
  #
  # Rate limits:
  #   GitHub GraphQL API: 5,000 points per hour per token.
  #   This query costs ~1 point, so even frequent syncs are safe.
  module GithubSponsorsChecker
    GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"

    # GraphQL query — viewerIsSponsoring is true when the authenticated user
    # is an active sponsor of the given login.
    SPONSORING_QUERY = <<~GRAPHQL
      query($login: String!) {
        user(login: $login) {
          viewerIsSponsoring
        }
      }
    GRAPHQL

    def self.sync_user(user)
      return unless SiteSetting.community_integrations_enabled
      return unless SiteSetting.community_integrations_github_sponsors_target_username.present?

      associated =
        UserAssociatedAccount.find_by(user_id: user.id, provider_name: "github")
      token = associated&.credentials&.dig("token")

      unless token.present?
        Rails.logger.debug(
          "GithubSponsorsChecker: no GitHub token for user #{user.id}; skipping.",
        )
        return
      end

      sponsoring = check_sponsoring(token)
      GroupSync.sync(user, SiteSetting.community_integrations_github_sponsors_group, sponsoring)
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    def self.check_sponsoring(token)
      response =
        Faraday.post(GITHUB_GRAPHQL_URL) do |req|
          req.headers["Authorization"] = "Bearer #{token}"
          req.headers["Content-Type"] = "application/json"
          req.headers["User-Agent"] = "discourse-community-integrations"
          req.body =
            {
              query: SPONSORING_QUERY,
              variables: {
                login: SiteSetting.community_integrations_github_sponsors_target_username,
              },
            }.to_json
        end

      unless response.status == 200
        Rails.logger.error(
          "GithubSponsorsChecker: HTTP #{response.status} from GitHub GraphQL: " \
            "#{response.body.truncate(200)}",
        )
        return nil
      end

      data = JSON.parse(response.body)

      if (errors = data["errors"]).present?
        Rails.logger.error(
          "GithubSponsorsChecker: GraphQL errors: #{errors.inspect}",
        )
        return nil
      end

      data.dig("data", "user", "viewerIsSponsoring") == true
    rescue => e
      Rails.logger.error("GithubSponsorsChecker#check_sponsoring error: #{e.message}")
      nil
    end
    private_class_method :check_sponsoring
  end
end
