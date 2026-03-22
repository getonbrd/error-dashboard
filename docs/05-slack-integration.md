# Slack Integration

The Error Dashboard sends rich notifications to Slack when new errors are logged and supports interactive actions (Resolve button) directly from Slack.

## Setup

### 1. Create a Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app
2. Under **Incoming Webhooks**, activate and create a webhook for your channel
3. Under **Interactivity & Shortcuts**, enable interactivity and set the Request URL to:
   ```
   https://error-dashboard.example.com/slack/interactions
   ```
4. Under **Basic Information**, copy the **Signing Secret**

### 2. Configure Environment Variables

| Variable | Description |
|----------|-------------|
| `SLACK_WEBHOOK_URL` | Incoming webhook URL (enables notifications) |
| `SLACK_SIGNING_SECRET` | App signing secret (required for interactive actions) |
| `DASHBOARD_BASE_URL` | Public URL of your dashboard (for "View Details" links) |

Slack notifications are automatically enabled when `SLACK_WEBHOOK_URL` is set.

## Notification Format

When a new error is logged, Slack receives a message with these blocks:

```
🔴 NoMethodError                                    ← Header with severity emoji
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔁 5x · 👤 User #42 · error                         ← Occurrence count, user, severity
───────────────────────────────────────────────────
`undefined method 'name' for nil:NilClass`           ← Error message
───────────────────────────────────────────────────
app/controllers/dashboard_controller.rb:15:in `show` ← First app-level backtrace line
───────────────────────────────────────────────────
🔗 https://app.example.com/dashboard                 ← Request URL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[View Source]  [Resolve ⚠️]                          ← Action buttons
───────────────────────────────────────────────────
View in dashboard                                    ← Link to error detail page
```

### Severity Indicators

| Emoji | Priority Level | Meaning |
|-------|---------------|---------|
| 🔴 | 3+ | Critical |
| 🟠 | 2 | High |
| 🟡 | 1 | Medium |
| ⚪ | 0 (default) | Low / Info |

### Notification Cooldown

To prevent flooding, notifications are throttled per error hash. The same error won't trigger a new Slack notification within the cooldown period.

```ruby
config.notification_cooldown_minutes = 15  # default
```

## Interactive Resolve Button

Clicking the **Resolve** button in Slack:

1. Marks the error as resolved (`resolved: true`, `resolved_at: Time.current`)
2. Replaces the original message with a confirmation showing who resolved it:
   ```
   ✅ Resolved by @username
   [View Details]
   ```

### Request Verification

All interactive requests from Slack are verified using HMAC-SHA256 signature verification:

1. Checks `X-Slack-Request-Timestamp` is within 5 minutes (replay protection)
2. Computes `HMAC-SHA256("v0:{timestamp}:{raw_body}")` using the signing secret
3. Compares against `X-Slack-Signature` header using constant-time comparison

Requests that fail verification are rejected with `401 Unauthorized`.

## Customizing the Notification

The Slack payload is built by `RailsErrorDashboard::Services::SlackPayloadBuilder`. You can override its methods in an initializer:

```ruby
# config/initializers/rails_error_dashboard.rb
RailsErrorDashboard::Services::SlackPayloadBuilder.class_eval do
  class << self
    def header_block(error_log)
      emoji = case error_log.priority_level
              when 3.. then ":red_circle:"
              when 2    then ":large_orange_circle:"
              when 1    then ":yellow_circle:"
              else           ":white_circle:"
              end

      {
        type: "header",
        text: { type: "plain_text", text: "#{emoji} #{error_log.error_type}", emoji: true }
      }
    end

    # Override other blocks: info_block, message_block, stacktrace_block,
    # request_block, actions_block, context_block
  end
end
```

Each method receives the `error_log` record and returns a Slack Block Kit hash.
