This creates custom discourse plugins for the discourse forum software. The plugins are used to add custom functionality to the forum, such as the ability to create custom badges or to add custom fields to user profiles. The plugins are written in Ruby and are stored in the `plugins` directory of the discourse repository. The plugins are loaded by the discourse application when it starts up, and they can be enabled or disabled by the forum administrators. The plugins can also be updated or removed as needed. The plugins are an important part of the discourse ecosystem, as they allow developers to extend the functionality of the forum and to create custom features that are not available in the core application.

The server is on a remote VPS located at https://forum.christitus.com. The server is running Ubuntu 24.04 and has the following specifications:
- CPU: 6 cores
- RAM: 6 GB
- Storage: 350 GB SSD
- Bandwidth: 1 Gbps

# Discourse Plugin Development — Copilot Instructions

You are an expert Discourse plugin developer. When helping build, debug, or extend a Discourse plugin, always follow these conventions and constraints derived from the official Discourse plugin documentation.

---

## Stack Overview

Discourse is a full-stack forum application:

- **Backend**: Ruby on Rails
- **Frontend**: Ember.js with Handlebars (`.hbs`) templates
- **Plugin system**: File-based — Discourse scans the `plugins/` directory at startup

---

## Plugin File Structure

Every plugin lives in `discourse/plugins/<plugin-name>/` and must follow this layout:

```
plugins/
└── my-plugin/
    ├── plugin.rb                          ← Required manifest + Ruby init
    ├── config/
    │   ├── settings.yml                   ← Custom site settings
    │   └── locales/
    │       ├── server.en.yml              ← Server-side i18n (settings labels etc.)
    │       └── client.en.yml              ← Client-side i18n (JS/HBS strings)
    └── assets/
        └── javascripts/
            └── discourse/
                ├── initializers/          ← Auto-executed on app load
                │   └── my-initializer.js
                └── connectors/            ← Plugin outlet connectors
                    └── <outlet-name>/
                        └── my-connector.hbs
```

> **Admin JS** goes under `assets/javascripts/admin/` instead of `assets/javascripts/discourse/`.

---

## `plugin.rb` — The Manifest

Every plugin **must** have a `plugin.rb`. This is the entry point Discourse looks for.

```ruby
# name: my-plugin
# about: A short description of what this plugin does
# version: 0.1.0
# authors: Your Name
# url: https://github.com/yourname/my-plugin

enabled_site_setting :my_plugin_enabled
```

### Rules for `plugin.rb`

- Metadata comments (`# name:`, `# about:`, etc.) are **required** and must come first.
- `enabled_site_setting :my_plugin_enabled` declares which setting toggles the plugin on/off. This makes the **Settings** button appear on `/admin/plugins`.
- All your plugin's site settings should share a common prefix (e.g., `my_plugin_`) for the settings filter to work correctly.
- Use this file to `require` Ruby files, register assets, add routes, extend serializers, and hook into Rails.

### Generating a plugin skeleton

```bash
# From the discourse root:
rake plugin:create[my-plugin-name]
```

Or clone the official skeleton: https://github.com/discourse/discourse-plugin-skeleton

---

## JavaScript Initializers

Files in `assets/javascripts/discourse/initializers/` are **automatically executed** when the Discourse Ember app loads.

```js
// assets/javascripts/discourse/initializers/my-initializer.js
export default {
  name: "my-initializer",   // Must be globally unique across all plugins
  initialize() {
    // Runs once on app boot
  },
};
```

### Rules

- `name` must be unique — use your plugin name as a prefix to avoid collisions.
- `initialize()` receives the Ember application container as an argument if needed: `initialize(container)`.
- Do not perform side effects that should be guarded by a site setting here without checking `this.siteSettings` via the container.

---

## Plugin Outlets (Extending the UI)

Discourse templates contain `<PluginOutlet />` markers that are extension points for plugins.

### Finding outlets

```bash
# List all plugin outlets in the Discourse codebase
git grep "<PluginOutlet" -- "*.hbs"
```

Or enable the Developer Toolbar on a running Discourse by typing `enableDevTools()` in the browser console, then clicking the plug icon.

### Connecting to an outlet

Create a `.hbs` file at the matching connector path:

```
plugins/my-plugin/assets/javascripts/discourse/connectors/<outlet-name>/<unique-name>.hbs
```

**Example** — if the Discourse template has:

```hbs
<PluginOutlet @name="topic-above-posts" />
```

Create:

```
plugins/my-plugin/assets/javascripts/discourse/connectors/topic-above-posts/my-banner.hbs
```

```hbs
{{! my-banner.hbs }}
<div class="my-plugin-banner">Hello from my plugin!</div>
```

### Rules for connectors

- The directory name **must exactly match** the outlet name (case-sensitive).
- The filename must be **unique across all plugins** — use descriptive, plugin-prefixed names.
- Connectors are **additive** — they inject content, they don't replace templates.
- To replace or remove existing UI elements you need JavaScript-based overrides, not outlet connectors.
- All `.hbs` and `.js` files in a plugin are loaded automatically — no `register_asset` needed.

---

## Custom Site Settings

### 1. `config/settings.yml`

```yaml
plugins:
  my_plugin_enabled:
    default: true
    client: true
  my_plugin_max_items:
    default: 10
    client: true
  my_plugin_secret_key:
    default: ""
    client: false   # Server-only — not sent to the browser
```

- **`default`** determines the setting type: `true/false` → boolean, integer → integer, string → string.
- **`client: true`** sends the setting to the Ember frontend (included in the public JS payload). Only set this for non-sensitive settings.
- All settings for your plugin must share the same prefix (e.g., `my_plugin_`) for the admin settings filter to work.

### 2. `config/locales/server.en.yml`

Provide English labels for your settings (required):

```yaml
en:
  site_settings:
    my_plugin_enabled: "Enable My Plugin?"
    my_plugin_max_items: "Maximum number of items to display"
    my_plugin_secret_key: "Secret API key for My Plugin"
```

### 3. Declare the enabled setting in `plugin.rb`

```ruby
enabled_site_setting :my_plugin_enabled
```

### Accessing settings

| Context | Syntax |
|---|---|
| Ember JS / component | `this.siteSettings.my_plugin_enabled` |
| Handlebars template | `{{siteSettings.my_plugin_enabled}}` |
| Ruby / Rails | `SiteSetting.my_plugin_enabled` |

> ⚠️ Note: Ruby uses `SiteSetting` (singular), not `SiteSettings`.

---

## Development Workflow

### Starting the server

```bash
bin/ember-cli -u
```

### When to restart

- **Always restart** after changes to `plugin.rb`, Ruby files, or `config/settings.yml`.
- For JS/HBS changes: usually a browser refresh suffices, but restart if changes aren't picked up.

### Clearing the cache

```bash
rm -rf tmp && bin/ember-cli -u
```

Run this when you create or delete files and changes aren't reflected.

### Verifying the plugin loaded

Visit `/admin/plugins` (as an admin). Your plugin should appear in the list.

### Git workflow for plugin development

Keep your plugin in a separate repo and use a symlink into `discourse/plugins/`:

```bash
# From the discourse plugins directory
ln -s ~/code/my-discourse-plugin .
```

> **Docker note:** Symlinks won't cross Docker volume boundaries. Instead, mount the plugin as an additional Docker volume in your dev container config.

---

## Ruby Backend Patterns

### Adding routes

```ruby
# plugin.rb
Discourse::Application.routes.append do
  get "/my-plugin/data" => "my_plugin/data#index"
end
```

### Extending serializers

```ruby
# plugin.rb
add_to_serializer(:basic_user, :my_custom_field) do
  object.custom_fields["my_custom_field"]
end
```

### PluginStore (key-value storage for plugins)

```ruby
# Store
PluginStore.set("my-plugin", "key", value)

# Retrieve
PluginStore.get("my-plugin", "key")
```

### Plugin API hooks (in `plugin.rb`)

```ruby
after_initialize do
  # Code here runs after Discourse is fully initialized
  # Safe to reference models and services
end
```

---

## Common Gotchas

| Issue | Fix |
|---|---|
| Plugin not showing in `/admin/plugins` | Restart the server; check that `plugin.rb` exists and metadata is valid |
| JS changes not reflected | Clear `tmp/` and restart |
| Settings not loading | Validate YAML at yamllint.com; restart after any changes to `settings.yml` |
| Widget with state causes infinite loop | Add `buildKey: () => 'my-widget-name'` to your widget definition |
| Connector not rendering | Double-check outlet name spelling (exact match, case-sensitive) |
| Settings button not showing on `/admin/plugins` | Ensure all settings share the plugin prefix and `enabled_site_setting` is declared |
| `SiteSettings` not found in Ruby | Use `SiteSetting` (singular) in Ruby; `siteSettings` (camelCase) in JS |

---

## Key Reference Links

- Official plugin series: https://meta.discourse.org/t/developing-discourse-plugins-part-1-create-a-basic-plugin/30515
- Plugin outlets guide: https://meta.discourse.org/t/using-plugin-outlet-connectors-from-a-theme-or-plugin/32727
- Plugin skeleton repo: https://github.com/discourse/discourse-plugin-skeleton
- Discourse source (for finding outlets): https://github.com/discourse/discourse

---

## Conventions to Always Follow

1. **Name every initializer uniquely** — prefix with the plugin name.
2. **Name every connector file uniquely** — prefix with the plugin name.
3. **Prefix all site settings** with the plugin name (e.g., `my_plugin_`).
4. **Never edit Discourse core files** — use outlets, serializer extensions, and API hooks instead.
5. **Keep `plugin.rb` metadata complete** — name, about, version, authors, url are all required.
6. **Always clear `tmp/` when adding or removing files**, not just editing them.
7. **Use `client: false`** for any setting that contains secrets or that the browser doesn't need.
8. **Provide i18n translations** for every setting in `config/locales/server.en.yml` before testing.