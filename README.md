# ChrisTitusTech Community Forum

Self-hosted Discourse forum with automated group membership sync for:
- **GitHub Sponsors** — via GitHub OAuth + GraphQL API
- **Twitch Subscribers** — via Twitch OAuth + Helix API
- **Patreon Members** — via the bundled `discourse-patreon` plugin
- **YouTube Members** — via Google OAuth (user connects account) + YouTube Data API v3

---

## Repository Layout

```
community/                          ← this repo (clone to /var/discourse)
├── containers/
│   └── app.yml                     ← Discourse Docker configuration
├── scripts/
│   └── setup.sh                    ← one-time VPS preparation script
└── plugins/
    └── discourse-community-integrations/   ← custom Discourse plugin
        ├── plugin.rb
        ├── config/settings.yml
        ├── app/lib/
        │   ├── auth/               ← OAuth authenticators
        │   └── community_integrations/  ← membership checker modules
        └── jobs/                   ← background + scheduled jobs
```

> **Note:** For Docker deployment the plugin must be published as a standalone repository.
> See [Publishing the Plugin](#publishing-the-plugin) below.

---

## Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU      | 2 vCPU  | 6 vCPU (your config) |
| RAM      | 2 GB    | 6 GB (your config) |
| Disk     | 20 GB   | 350 GB SSD (your config) |
| OS       | Ubuntu 22.04 LTS |  |
| Docker   | 24.0+   |  |
| Ports    | 22, 80, 443 open |  |

---

## Phase 1: VPS Preparation

SSH into the VPS as root, then run the setup script:

```bash
curl -fsSL https://raw.githubusercontent.com/ChrisTitusTech/community/main/scripts/setup.sh | bash
```

This installs Docker, configures UFW, creates the `discourse` system user, and clones `discourse_docker`.

---

## Phase 2: DNS & Email

1. **DNS** — Add an A record pointing your forum domain to the VPS IP. Wait for propagation before bootstrapping (Let's Encrypt requires port 80 to be reachable).

2. **SMTP** — Discourse requires transactional email for signups and notifications. Recommended providers:
   - [Mailgun](https://mailgun.com) — free tier 1,000 emails/month
   - [Postmark](https://postmarkapp.com) — free tier 100/month
   - [SendGrid](https://sendgrid.com) — free tier 100/day

---

## Phase 3: Configure `app.yml`

```bash
cp /var/discourse/containers/app.yml.sample /var/discourse/containers/app.yml
# or copy from this repo:
cp /path/to/community/containers/app.yml /var/discourse/containers/app.yml
```

Edit all `REPLACE_WITH_*` placeholders in `containers/app.yml`.

---

## Phase 4: Bootstrap & Launch

```bash
cd /var/discourse
./launcher bootstrap app   # ~5–10 minutes; downloads images, compiles assets
./launcher start app       # starts the forum
```

Visit your domain — the setup wizard runs on first load.

---

## Phase 5: Create Discourse Groups

In **Admin → Groups**, create these four groups exactly as named (or update the plugin settings to match your choice):

| Group Name | Platform |
|------------|----------|
| `GitHub Sponsors` | GitHub |
| `Twitch Subscriber` | Twitch |
| `Patron` | Patreon |
| `YouTube Member` | YouTube |

---

## Phase 6: OAuth App Setup

### GitHub (Sponsors)

1. Go to <https://github.com/settings/developers> → **OAuth Apps** → **New OAuth App**
2. Set **Authorization callback URL** to `https://YOUR_DOMAIN/auth/github/callback`
3. Copy the **Client ID** and **Client Secret** into Discourse:
   **Admin → Settings → Login → GitHub**

### Twitch (Subscribers)

1. Go to <https://dev.twitch.tv/console> → **Register Your Application**
2. Set **OAuth Redirect URL** to `https://YOUR_DOMAIN/auth/twitch/callback`
3. Choose **Category: Website Integration**
4. Copy **Client ID** and **Client Secret** into:
   **Admin → Settings → Plugins → Community Integrations**
5. Set **Twitch Broadcaster ID** — find your numeric channel ID at
   `https://api.twitch.tv/helix/users?login=YOUR_USERNAME` (use a test token) or via <https://www.streamweasels.com/tools/convert-twitch-username-to-user-id/>

### Patreon

1. Go to <https://www.patreon.com/portal/registration/register-clients>
2. Set **Redirect URI** to `https://YOUR_DOMAIN/auth/patreon/callback`
3. Configure in **Admin → Settings → Plugins → Patreon**
4. Log in as the creator account once to capture the creator OAuth token
5. Map reward tiers to the **Patron** group in the Patreon plugin settings

### YouTube (Members)

YouTube Membership verification uses a **two-token approach**:

| Token | Who | Scope | Purpose |
|-------|-----|-------|---------|
| **Creator token** | Chris (channel owner) | `youtube.channel-memberships.creator` | Query the member list |
| **User token** | Each forum member | `youtube.readonly` | Retrieve their YouTube channel ID |

#### A. Create the Google OAuth App

1. Go to <https://console.cloud.google.com> → create a new project (e.g. `community-forum`)
2. Enable: **YouTube Data API v3** and **Google+ API** (for profile)
3. Under **APIs & Services → Credentials** → **Create OAuth 2.0 Client ID** (Web Application)
4. Add **Authorized redirect URIs**:
   - `https://YOUR_DOMAIN/auth/google_oauth2/callback` (regular Google login)
   - `https://YOUR_DOMAIN/auth/youtube/callback` (YouTube connect flow)
5. Copy **Client ID** and **Client Secret**

#### B. Get the Creator Refresh Token (one-time setup)

Run this locally to get Chris's channel-memberships refresh token:

```bash
# Install google-auth-oauthlib if needed: pip install google-auth-oauthlib
python3 scripts/get_youtube_creator_token.py
```

This outputs a refresh token — paste it into:
**Admin → Settings → Plugins → Community Integrations → YouTube Creator Refresh Token**

#### C. Configure in Discourse

- **Admin → Settings → Login → Google** — enter the Client ID and Secret from step A
- **Admin → Settings → Plugins → Community Integrations** — enter YouTube Client ID, Secret, Creator Refresh Token, and Channel ID

---

## Phase 7: Verify Integrations

```bash
# Check Discourse logs for any auth or sync errors
sudo /var/discourse/launcher logs app | grep -E "(TwitchChecker|GithubSponsor|YoutubeMember|ERROR)"

# Manually trigger the full sync job from the Rails console
sudo /var/discourse/launcher enter app
rails r "Jobs::SyncCommunityIntegrations.new.execute({})"
```

In **Admin → Groups**, confirm the member counts reflect active sponsors/subscribers/members.

---

## Publishing the Plugin

The `plugins/discourse-community-integrations/` directory must be pushed as its own repository so Discourse's Docker setup can `git clone` it during bootstrap.

```bash
cd plugins/discourse-community-integrations
git init
git remote add origin https://github.com/ChrisTitusTech/discourse-community-integrations.git
git add .
git commit -m "Initial plugin scaffold"
git push -u origin main
```

After publishing, `containers/app.yml` already references the correct URL.

---

## Updating Discourse

```bash
cd /var/discourse
git pull
./launcher rebuild app   # rebuilds with latest Discourse + plugins
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Let's Encrypt fails | Ensure DNS is pointing to VPS and port 80 is open |
| Emails not sending | Check SMTP credentials; run `rails r "UserNotifications.test_email('you@example.com')"` |
| Twitch group not assigned | Confirm `twitch_broadcaster_id` is a numeric ID, not a username |
| GitHub group not assigned | Ensure the user's GitHub OAuth token has not expired (GitHub tokens rarely expire unless revoked) |
| YouTube check fails with 403 | Re-run `get_youtube_creator_token.py` — the creator refresh token may have been revoked |
| YouTube API quota exceeded | Default is 10,000 units/day; request an increase in GCP Console or reduce sync frequency |
