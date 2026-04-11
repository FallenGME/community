# frozen_string_literal: true

module OmniAuth
  module Strategies
    # Lightweight Twitch OAuth2 strategy built on top of omniauth-oauth2
    # (already a Discourse dependency — no extra gem required).
    #
    # Scopes requested:
    #   user:read:email         — get the user's verified email address
    #   user:read:subscriptions — let the user check their own subscription status
    #                             to a specified broadcaster via the Helix API
    class Twitch < OmniAuth::Strategies::OAuth2
      option :name, "twitch"

      option :client_options,
             site: "https://api.twitch.tv",
             authorize_url: "https://id.twitch.tv/oauth2/authorize",
             token_url: "https://id.twitch.tv/oauth2/token"

      option :scope, "user:read:email user:read:subscriptions"

      # Use Twitch's numeric user ID as the UID so it never changes even if
      # the user renames their channel.
      uid { raw_info["id"] }

      info do
        {
          name: raw_info["display_name"],
          email: raw_info["email"],
          nickname: raw_info["login"],
          image: raw_info["profile_image_url"],
        }
      end

      extra { { raw_info: raw_info } }

      def raw_info
        @raw_info ||=
          begin
            # Twitch's Helix API requires both an Authorization bearer token
            # AND the Client-ID header; omitting either returns 401/400.
            response =
              access_token.get(
                "https://api.twitch.tv/helix/users",
                headers: {
                  "Client-ID" => options.client_id,
                  "Authorization" => "Bearer #{access_token.token}",
                },
              )
            JSON.parse(response.body)["data"].first
          end
      end

      # Override callback_url so the redirect URI matches the value registered
      # in the Twitch developer console exactly (no trailing slashes / params).
      def callback_url
        full_host + script_name + callback_path
      end
    end
  end
end
