# Source Code Integration

The Error Dashboard links backtrace frames to your source code on GitHub, letting you click directly from an error to the exact file and line that caused it.

## Configuration

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard.configure do |config|
  config.enable_source_code_integration = true
  config.git_repository_url = "https://github.com/your-org/your-repo"
  config.git_sha = ENV["GIT_SHA"]
  config.source_code_context_lines = 10
  config.only_show_app_code_source = true
end
```

| Setting | Description |
|---------|-------------|
| `enable_source_code_integration` | Enables clickable backtrace links |
| `git_repository_url` | GitHub repository URL (no trailing slash) |
| `git_sha` | Commit SHA to link to (usually from CI/CD) |
| `source_code_context_lines` | Lines of context shown before/after the error line |
| `only_show_app_code_source` | Hide gem/vendor frames, only show app code |

## How It Works

1. When an error is ingested, `app_version` or `git_sha` identifies the commit
2. Backtrace frames are parsed for file path and line number
3. The web UI and Slack "View Source" button link to:
   ```
   https://github.com/your-org/your-repo/blob/<git_sha>/path/to/file.rb#L42
   ```

## Setting git_sha

The `git_sha` value typically comes from your CI/CD pipeline:

### Kubernetes (IMAGE_TAG)

If your image tags are git SHAs (e.g., `sha-abc1234`), the dashboard extracts the SHA automatically:

```ruby
# In the initializer, git_sha falls back to app_version with "sha-" stripped
def git_sha
  super.presence || app_version&.delete_prefix("sha-")
end
```

Set `GIT_SHA` or `IMAGE_TAG` in your deployment:

```yaml
env:
  - name: GIT_SHA
    value: "abc1234def5678"
```

### Heroku

Heroku sets `HEROKU_SLUG_COMMIT` automatically. The client's `ErrorReporter` module converts it:

```ruby
def app_version
  ENV["IMAGE_TAG"] || "sha-#{ENV['HEROKU_SLUG_COMMIT']&.slice(0, 7)}" || "unknown"
end
```

### GitHub Actions

```yaml
- name: Deploy
  env:
    GIT_SHA: ${{ github.sha }}
```

## Slack "View Source" Button

When source code integration is enabled, Slack notifications include a "View Source" button that links to the relevant file on GitHub at the exact commit and line number.
