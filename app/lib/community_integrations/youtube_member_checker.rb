# frozen_string_literal: true

module CommunityIntegrations
  # Checks whether a Discourse user is an active YouTube channel member and
  # syncs their Discourse group membership accordingly.
  #
  # ── Two-token design ────────────────────────────────────────────────────────
  #
  # YouTube's Memberships API is designed for *channel owners*, not members.
  # There is no "am I a member of channel X?" endpoint available to subscribers.
  # Instead this module uses two separate tokens:
  #
  #   1. USER token  (youtube.readonly scope)
  #      Stored in UserAssociatedAccount (provider_name: "youtube") when the
  #      user clicks "Connect YouTube" in their preferences.
  #      Used to retrieve the user's YouTube channel ID via:
  #        GET /youtube/v3/channels?part=id&mine=true
  #
  #   2. CREATOR token  (youtube.channel-memberships.creator scope)
  #      The channel owner's (Chris's) long-lived refresh token, stored as
  #      the site setting `youtube_creator_refresh_token`.
  #      Used to query:
  #        GET /youtube/v3/memberships?part=snippet
  #                                   &filterByMemberChannelId=<USER_CHANNEL_ID>
  #                                   &maxResults=1
  #      Returns a membership record if the user is a channel member.
  #
  # ── API quota note ──────────────────────────────────────────────────────────
  # YouTube Data API v3 default quota: 10,000 units/day.
  # Each memberships.list call costs 1 unit.
  # Each channels.list call costs 1 unit.
  # At the default 6-hour sync for 1,000 users: 1,000 * 2 * 4 = 8,000 units/day.
  # For larger communities request a quota increase in GCP Console.
  module YoutubeMemberChecker
    GOOGLE_TOKEN_URL      = "https://oauth2.googleapis.com/token"
    CHANNELS_URL          = "https://www.googleapis.com/youtube/v3/channels"
    MEMBERSHIPS_URL       = "https://www.googleapis.com/youtube/v3/memberships"
    CREATOR_TOKEN_CACHE   = "youtube_creator_access_token"

    def self.sync_user(user)
      return unless SiteSetting.community_integrations_enabled
      return unless SiteSetting.community_integrations_youtube_channel_id.present?
      return unless SiteSetting.community_integrations_youtube_creator_refresh_token.present?

      associated =
        UserAssociatedAccount.find_by(user_id: user.id, provider_name: "youtube")
      unless associated
        Rails.logger.debug(
          "YoutubeMemberChecker: user #{user.id} has not connected YouTube; skipping.",
        )
        return
      end

      user_token = refreshed_user_token(associated)
      unless user_token
        Rails.logger.warn(
          "YoutubeMemberChecker: could not obtain user token for user #{user.id}; skipping.",
        )
        return
      end

      user_channel_id = fetch_user_channel_id(user_token)
      unless user_channel_id
        Rails.logger.warn(
          "YoutubeMemberChecker: could not retrieve YouTube channel ID for user #{user.id}.",
        )
        return
      end

      creator_token = creator_access_token
      unless creator_token
        Rails.logger.error("YoutubeMemberChecker: could not obtain creator token; skipping sync.")
        return
      end

      member = check_membership(creator_token, user_channel_id)
      GroupSync.sync(user, SiteSetting.community_integrations_youtube_member_group, member)
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    # Retrieves the user's YouTube channel ID using their OAuth token.
    def self.fetch_user_channel_id(user_token)
      response =
        Faraday.get(
          CHANNELS_URL,
          { part: "id", mine: "true" },
          { "Authorization" => "Bearer #{user_token}" },
        )

      unless response.status == 200
        Rails.logger.error(
          "YoutubeMemberChecker: channels.list HTTP #{response.status}: " \
            "#{response.body.truncate(200)}",
        )
        return nil
      end

      JSON.parse(response.body)["items"]&.first&.dig("id")
    rescue => e
      Rails.logger.error("YoutubeMemberChecker#fetch_user_channel_id error: #{e.message}")
      nil
    end
    private_class_method :fetch_user_channel_id

    # Checks whether user_channel_id appears in the channel's member list.
    # Uses the CREATOR's token — only channel owners can query this endpoint.
    def self.check_membership(creator_token, user_channel_id)
      response =
        Faraday.get(
          MEMBERSHIPS_URL,
          {
            part: "snippet",
            filterByMemberChannelId: user_channel_id,
            maxResults: 1,
          },
          { "Authorization" => "Bearer #{creator_token}" },
        )

      case response.status
      when 200
        data = JSON.parse(response.body)
        target = SiteSetting.community_integrations_youtube_channel_id
        data["items"]&.any? { |item| item.dig("snippet", "creatorChannelId") == target } || false
      when 403
        Rails.logger.error(
          "YoutubeMemberChecker: 403 Forbidden from memberships.list — " \
            "ensure the creator token has youtube.channel-memberships.creator scope.",
        )
        nil
      else
        Rails.logger.error(
          "YoutubeMemberChecker: HTTP #{response.status} from memberships.list: " \
            "#{response.body.truncate(200)}",
        )
        nil
      end
    rescue => e
      Rails.logger.error("YoutubeMemberChecker#check_membership error: #{e.message}")
      nil
    end
    private_class_method :check_membership

    # ── Creator token (channel owner) ─────────────────────────────────────────

    # Returns a cached or freshly refreshed access token for the channel owner.
    # The result is cached in Discourse's Redis-backed cache for (expires_in - 5 min).
    def self.creator_access_token
      cached = Discourse.cache.read(CREATOR_TOKEN_CACHE)
      return cached if cached.present?

      refresh_token = SiteSetting.community_integrations_youtube_creator_refresh_token
      return nil unless refresh_token.present?

      response =
        Faraday.post(GOOGLE_TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body =
            URI.encode_www_form(
              grant_type: "refresh_token",
              refresh_token: refresh_token,
              client_id: SiteSetting.community_integrations_youtube_client_id,
              client_secret: SiteSetting.community_integrations_youtube_client_secret,
            )
        end

      unless response.status == 200
        Rails.logger.error(
          "YoutubeMemberChecker: creator token refresh failed (HTTP #{response.status}): " \
            "#{response.body.truncate(200)}",
        )
        return nil
      end

      data = JSON.parse(response.body)
      token = data["access_token"]
      ttl = [data["expires_in"].to_i - 300, 60].max

      Discourse.cache.write(CREATOR_TOKEN_CACHE, token, expires_in: ttl)
      token
    rescue => e
      Rails.logger.error("YoutubeMemberChecker#creator_access_token error: #{e.message}")
      nil
    end
    private_class_method :creator_access_token

    # ── User token refresh (google/youtube.readonly) ───────────────────────────

    def self.refreshed_user_token(associated)
      extra = associated.extra || {}
      token = associated.credentials&.dig("token")

      return token if token.present? && !token_expired?(extra)

      refresh_token = extra["refresh_token"]
      return nil unless refresh_token.present?

      response =
        Faraday.post(GOOGLE_TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body =
            URI.encode_www_form(
              grant_type: "refresh_token",
              refresh_token: refresh_token,
              client_id: SiteSetting.community_integrations_youtube_client_id,
              client_secret: SiteSetting.community_integrations_youtube_client_secret,
            )
        end

      unless response.status == 200
        Rails.logger.error(
          "YoutubeMemberChecker: user token refresh failed (HTTP #{response.status}) " \
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
            "token_expires_at" => Time.now.to_i + data["expires_in"].to_i,
          ),
      )

      new_token
    rescue => e
      Rails.logger.error("YoutubeMemberChecker#refreshed_user_token error: #{e.message}")
      nil
    end
    private_class_method :refreshed_user_token

    def self.token_expired?(extra)
      expires_at = extra["token_expires_at"].to_i
      return true if expires_at.zero?
      Time.now.to_i >= expires_at - 300
    end
    private_class_method :token_expired?
  end
end
