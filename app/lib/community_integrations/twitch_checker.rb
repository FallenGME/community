# frozen_string_literal: true

module CommunityIntegrations
  # Checks whether a Discourse user is currently subscribed to the configured
  # Twitch channel and syncs their group membership accordingly.
  #
  # API used:
  #   GET https://api.twitch.tv/helix/subscriptions/user
  #     ?broadcaster_id=<BROADCASTER_ID>&user_id=<VIEWER_ID>
  #
  # Authentication:
  #   The viewer's own OAuth token with the `user:read:subscriptions` scope.
  #   This means the user must have logged in via Twitch at least once.
  #   The endpoint returns 200 if subscribed, 404 if not.
  #
  # Token refresh:
  #   Twitch access tokens expire after ~4 hours.  This module refreshes them
  #   automatically using the stored refresh token before each API call.
  module TwitchChecker
    TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token"
    TWITCH_SUBSCRIPTIONS_URL = "https://api.twitch.tv/helix/subscriptions/user"

    # Entry point — call this from a job or the scheduled sync.
    def self.sync_user(user)
      return unless SiteSetting.community_integrations_enabled
      return unless SiteSetting.community_integrations_twitch_broadcaster_id.present?
      return unless SiteSetting.community_integrations_twitch_client_id.present?

      associated =
        UserAssociatedAccount.find_by(user_id: user.id, provider_name: "twitch")
      return unless associated

      token = refreshed_token(associated)
      subscribed =
        if token
          check_subscription(token, associated.provider_uid)
        else
          Rails.logger.warn(
            "TwitchChecker: could not obtain valid token for user #{user.id}; skipping.",
          )
          nil
        end

      GroupSync.sync(user, SiteSetting.community_integrations_twitch_subscriber_group, subscribed)
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    def self.check_subscription(token, twitch_user_id)
      response =
        Faraday.get(
          TWITCH_SUBSCRIPTIONS_URL,
          {
            broadcaster_id: SiteSetting.community_integrations_twitch_broadcaster_id,
            user_id: twitch_user_id,
          },
          {
            "Client-ID" => SiteSetting.community_integrations_twitch_client_id,
            "Authorization" => "Bearer #{token}",
          },
        )

      case response.status
      when 200
        true
      when 404
        false
      else
        Rails.logger.error(
          "TwitchChecker: unexpected HTTP #{response.status} for user #{twitch_user_id}: " \
            "#{response.body.truncate(200)}",
        )
        nil
      end
    rescue => e
      Rails.logger.error("TwitchChecker#check_subscription error: #{e.message}")
      nil
    end
    private_class_method :check_subscription

    # Returns a valid (possibly freshly refreshed) access token, or nil.
    def self.refreshed_token(associated)
      extra = associated.extra || {}
      token = associated.credentials&.dig("token")

      return token if token.present? && !token_expired?(extra)

      refresh_token = extra["refresh_token"]
      return nil unless refresh_token.present?

      response =
        Faraday.post(TWITCH_TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body =
            URI.encode_www_form(
              grant_type: "refresh_token",
              refresh_token: refresh_token,
              client_id: SiteSetting.community_integrations_twitch_client_id,
              client_secret: SiteSetting.community_integrations_twitch_client_secret,
            )
        end

      unless response.status == 200
        Rails.logger.error(
          "TwitchChecker: token refresh failed (HTTP #{response.status}) " \
            "for associated account #{associated.id}",
        )
        return nil
      end

      data = JSON.parse(response.body)
      new_token = data["access_token"]

      associated.update!(
        credentials: (associated.credentials || {}).merge("token" => new_token),
        extra:
          extra.merge(
            "refresh_token" => data["refresh_token"] || refresh_token,
            "token_expires_at" => Time.now.to_i + data["expires_in"].to_i,
          ),
      )

      new_token
    rescue => e
      Rails.logger.error("TwitchChecker#refreshed_token error: #{e.message}")
      nil
    end
    private_class_method :refreshed_token

    # True when the stored token is expired (or within a 5-minute safety buffer).
    def self.token_expired?(extra)
      expires_at = extra["token_expires_at"].to_i
      return true if expires_at.zero?
      Time.now.to_i >= expires_at - 300
    end
    private_class_method :token_expired?
  end
end
