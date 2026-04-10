#!/usr/bin/env python3
"""
get_youtube_creator_token.py
────────────────────────────
One-time helper to obtain a long-lived Google OAuth2 refresh token for the
YouTube CHANNEL OWNER account with the youtube.channel-memberships.creator
scope.

Run this locally (not on the server) as the channel owner:

    pip install google-auth-oauthlib
    python3 scripts/get_youtube_creator_token.py

Then paste the printed refresh_token into:
    Admin → Settings → Plugins → Community Integrations
    → YouTube Creator Refresh Token

Requirements:
    pip install google-auth-oauthlib

You will need your Google OAuth2 Client ID and Client Secret from the GCP
Console. Use the SAME OAuth app configured in Discourse (or a separate one
— both work as long as it has the YouTube Data API v3 enabled).
"""

import json
import os

try:
    from google_auth_oauthlib.flow import InstalledAppFlow
except ImportError:
    raise SystemExit(
        "google-auth-oauthlib is not installed.\n"
        "Run: pip install google-auth-oauthlib"
    )

SCOPES = [
    # Required to list channel members (creator-side endpoint)
    "https://www.googleapis.com/auth/youtube.channel-memberships.creator",
    # Basic identity — needed to verify the token is for the right account
    "https://www.googleapis.com/auth/youtube.readonly",
]

def main():
    client_id = os.environ.get("YOUTUBE_CLIENT_ID") or input("Enter Google OAuth2 Client ID: ").strip()
    client_secret = os.environ.get("YOUTUBE_CLIENT_SECRET") or input("Enter Google OAuth2 Client Secret: ").strip()

    client_config = {
        "installed": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["urn:ietf:wg:oauth:2.0:oob", "http://localhost"],
        }
    }

    flow = InstalledAppFlow.from_client_config(client_config, scopes=SCOPES)

    # Run a local server on port 8080 to capture the auth code automatically.
    # If port 8080 is in use, change the port number below.
    credentials = flow.run_local_server(port=8080)

    print("\n" + "=" * 60)
    print("SUCCESS — copy the refresh_token below into Discourse:")
    print("=" * 60)
    print(f"\nrefresh_token: {credentials.refresh_token}\n")
    print("=" * 60)
    print("\nAlso verify these match your Discourse plugin settings:")
    print(f"  client_id:     {credentials.client_id}")
    print(f"  client_secret: {credentials.client_secret}")
    print(
        "\nDo NOT share this refresh token. It gives read access to your"
        " YouTube channel member list."
    )

if __name__ == "__main__":
    main()
