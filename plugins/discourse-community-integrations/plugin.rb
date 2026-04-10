# frozen_string_literal: true

# name: discourse-community-integrations
# about: Syncs GitHub Sponsors, Twitch Subscribers, and YouTube Members to Discourse groups
# version: 0.1.0
# authors: ChrisTitusTech
# url: https://github.com/ChrisTitusTech/discourse-community-integrations

enabled_site_setting :community_integrations_enabled

# ── Load auth strategies & authenticators ─────────────────────────────────────
require_relative "app/lib/auth/twitch_strategy"
require_relative "app/lib/auth/twitch_authenticator"
require_relative "app/lib/auth/youtube_authenticator"

# ── Load membership checker modules ───────────────────────────────────────────
require_relative "app/lib/community_integrations/group_sync"
require_relative "app/lib/community_integrations/twitch_checker"
require_relative "app/lib/community_integrations/github_sponsors_checker"
require_relative "app/lib/community_integrations/youtube_member_checker"

# ── Register OAuth providers ───────────────────────────────────────────────────
auth_provider authenticator: Auth::TwitchAuthenticator.new
auth_provider authenticator: Auth::YouTubeAuthenticator.new

after_initialize do
  # ── GitHub Sponsors check on GitHub login ───────────────────────────────────
  # Runs asynchronously after every successful GitHub OAuth so the login
  # response time is unaffected by the GraphQL API call.
  on(:after_auth) do |authenticator, result|
    next unless result.user
    next unless SiteSetting.community_integrations_enabled

    case authenticator.name
    when "github"
      Jobs.enqueue(:check_github_sponsor, user_id: result.user.id)
    when "google_oauth2"
      # Standard Google login — no YouTube scope on this token; skip YouTube check.
      # YouTube membership is checked after the dedicated YouTube connect flow
      # handled by Auth::YouTubeAuthenticator (provider name: "youtube").
      nil
    when "youtube"
      Jobs.enqueue(:check_youtube_member, user_id: result.user.id)
    when "twitch"
      Jobs.enqueue(:check_twitch_subscriber, user_id: result.user.id)
    end
  end
end
