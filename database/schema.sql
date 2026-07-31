-- Notification & Campaign Service - Canonical Production Schema (11 Tables)

-- 1. Core Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id VARCHAR(36) PRIMARY KEY,
    type VARCHAR(32) NOT NULL DEFAULT 'transactional',
    template_key VARCHAR(128) NOT NULL,
    template_version INT NOT NULL DEFAULT 1,
    locale VARCHAR(16) NOT NULL DEFAULT 'en',
    recipient_user_id VARCHAR(128),
    recipient_email VARCHAR(255),
    recipient_phone VARCHAR(64),
    data JSONB NOT NULL DEFAULT '{}',
    channels_requested JSONB NOT NULL DEFAULT '[]',
    status VARCHAR(32) NOT NULL DEFAULT 'processing',
    source_service VARCHAR(128) NOT NULL,
    correlation_id VARCHAR(128),
    idempotency_key VARCHAR(255) UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 2. Templates Management Table
CREATE TABLE IF NOT EXISTS templates (
    id VARCHAR(36) PRIMARY KEY,
    key VARCHAR(128) NOT NULL,
    version INT NOT NULL DEFAULT 1,
    locale VARCHAR(16) NOT NULL DEFAULT 'en',
    category VARCHAR(32) NOT NULL DEFAULT 'transactional',
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    required_vars JSONB NOT NULL DEFAULT '[]',
    optional_vars JSONB NOT NULL DEFAULT '[]',
    default_channels JSONB NOT NULL DEFAULT '["email"]',
    channels JSONB NOT NULL DEFAULT '{}',
    created_by VARCHAR(128) NOT NULL DEFAULT 'system',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_template_key_version_locale UNIQUE (key, version, locale)
);

-- 3. Audit Log of Sent Messages
CREATE TABLE IF NOT EXISTS sent_messages (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    channel VARCHAR(32) NOT NULL,
    template_key VARCHAR(128) NOT NULL,
    recipient_ref VARCHAR(255) NOT NULL,
    rendered_subject TEXT,
    rendered_body TEXT NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 4. Target Audiences / Segments
CREATE TABLE IF NOT EXISTS audiences (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    description TEXT,
    source_type VARCHAR(32) NOT NULL DEFAULT 'manual',
    filter_query TEXT,
    user_ids JSONB NOT NULL DEFAULT '[]',
    recipients JSONB NOT NULL DEFAULT '[]',
    count INT NOT NULL DEFAULT 0,
    created_by VARCHAR(128) NOT NULL DEFAULT 'system',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 5. Campaign Schedules & Definitions
CREATE TABLE IF NOT EXISTS campaigns (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    template_key VARCHAR(128) NOT NULL,
    channel VARCHAR(32) NOT NULL DEFAULT 'sms',
    audience_id VARCHAR(36) NOT NULL REFERENCES audiences(id) ON DELETE CASCADE,
    template_params JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(32) NOT NULL DEFAULT 'draft', -- draft, scheduled, active, completed, failed
    max_per_minute INT NOT NULL DEFAULT 1000,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    cron_expression VARCHAR(64),
    is_ab_testing BOOLEAN NOT NULL DEFAULT FALSE,
    ab_variants JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS channel VARCHAR(32) NOT NULL DEFAULT 'sms';
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS template_params JSONB NOT NULL DEFAULT '{}';
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS cron_expression VARCHAR(64);
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS is_ab_testing BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS ab_variants JSONB NOT NULL DEFAULT '[]';

-- 6. Service Identity Authorization Registry
CREATE TABLE IF NOT EXISTS service_identities (
    id VARCHAR(36) PRIMARY KEY,
    service_name VARCHAR(128) UNIQUE NOT NULL,
    api_key_hash VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 7. Service-to-Template Access Grants (RBAC)
CREATE TABLE IF NOT EXISTS service_template_grants (
    id VARCHAR(36) PRIMARY KEY,
    service_name VARCHAR(128) NOT NULL REFERENCES service_identities(service_name) ON DELETE CASCADE,
    template_key VARCHAR(128) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_service_template UNIQUE (service_name, template_key)
);

-- 8. User Preferences & Opt-Outs
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id VARCHAR(128) PRIMARY KEY,
    email_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    sms_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    push_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    category_opt_outs JSONB NOT NULL DEFAULT '{}',
    preferred_language VARCHAR(16) DEFAULT 'en',
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 9. Suppression List (Bounces, Unsubscribes, Complaints)
CREATE TABLE IF NOT EXISTS suppression_list (
    id VARCHAR(36) PRIMARY KEY,
    recipient_ref VARCHAR(255) UNIQUE NOT NULL,
    reason VARCHAR(128) NOT NULL, -- bounce, complaint, unsubscribe, manual
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 10. Channel Delivery Attempt History & Retries
CREATE TABLE IF NOT EXISTS notification_channel_attempts (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    channel VARCHAR(32) NOT NULL,
    attempt_number INT NOT NULL DEFAULT 1,
    provider VARCHAR(64) NOT NULL,
    provider_message_id VARCHAR(255),
    status VARCHAR(32) NOT NULL, -- sent, retryable_failure, terminal_failure
    error_reason TEXT,
    attempted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 11. Inbound Provider Webhook Events Tracking
CREATE TABLE IF NOT EXISTS delivery_events (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) REFERENCES notifications(id) ON DELETE SET NULL,
    provider VARCHAR(64) NOT NULL,
    provider_message_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(64) NOT NULL, -- delivered, opened, clicked, bounced, failed
    raw_payload JSONB NOT NULL DEFAULT '{}',
    received_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 12. Enabled Country & Locales Configuration
CREATE TABLE IF NOT EXISTS enabled_locales (
    code VARCHAR(16) PRIMARY KEY,
    country_code VARCHAR(8) NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 13. Channel Delivery Attempt History
CREATE TABLE IF NOT EXISTS notification_channel_attempts (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    channel VARCHAR(32) NOT NULL,
    attempt_number INT NOT NULL DEFAULT 1,
    provider VARCHAR(64) NOT NULL,
    provider_message_id VARCHAR(255),
    status VARCHAR(32) NOT NULL, -- sent, retryable_failure, terminal_failure, simulated_sent
    error_reason TEXT,
    attempted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for Query Performance
CREATE INDEX IF NOT EXISTS idx_notifications_idempotency ON notifications(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status);
CREATE INDEX IF NOT EXISTS idx_sent_messages_notification_id ON sent_messages(notification_id);
CREATE INDEX IF NOT EXISTS idx_sent_messages_sent_at ON sent_messages(sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_channel_attempts_notification_id ON notification_channel_attempts(notification_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_channel_attempts_notification_id ON notification_channel_attempts(notification_id);
CREATE INDEX IF NOT EXISTS idx_delivery_events_provider_msg ON delivery_events(provider, provider_message_id);

-- Seed Default Production Templates
INSERT INTO templates (id, key, version, locale, category, status, required_vars, default_channels, channels, created_by)
VALUES 
  ('tpl-welcome-001', 'welcome_email', 1, 'en', 'transactional', 'active', '["user_name"]', '["email", "sms", "push", "slack"]', '{"email": {"subject": "Welcome to our platform!", "body": "Hello {{user_name}}, welcome to our platform!"}, "sms": {"body": "Hi {{user_name}}, welcome aboard!"}, "push": {"subject": "Welcome!", "body": "Hi {{user_name}}, welcome aboard!"}, "slack": {"subject": "Welcome {{user_name}}", "body": "Hello {{user_name}}, welcome to our platform!"}}', 'system'),
  ('tpl-auth-otp-001', 'auth_otp', 1, 'en', 'transactional', 'active', '["otp_code"]', '["email", "sms", "push", "slack"]', '{"email": {"subject": "Your Verification Code", "body": "Your security code is: {{otp_code}}"}, "sms": {"body": "Your code is: {{otp_code}}"}, "push": {"subject": "Verification Code", "body": "Your code is {{otp_code}}"}, "slack": {"subject": "Verification Code", "body": "Your security code is: {{otp_code}}"}}', 'system'),
  ('tpl-campaign-001', 'campaign_newsletter', 1, 'en', 'marketing', 'active', '["user_name", "promo_code"]', '["email", "sms", "push", "slack"]', '{"email": {"subject": "Special Offer for {{user_name}}", "body": "Use code {{promo_code}} for 20% off!"}, "sms": {"body": "Hi {{user_name}}, use code {{promo_code}} for 20% off!"}, "push": {"subject": "Special Offer", "body": "Use code {{promo_code}} for 20% off!"}, "slack": {"subject": "Special Offer for {{user_name}}", "body": "Use code {{promo_code}} for 20% off!"}}', 'system'),
  ('tpl-bank-otp-001', 'transfer_otp', 1, 'en', 'transactional', 'active', '["user_name", "otp_code", "amount"]', '["sms", "email", "push"]', '{"sms": {"body": "Dear {{user_name}}, your OTP code for transfer of {{amount}} is {{otp_code}}. Valid for 5 minutes."}, "email": {"subject": "Security Verification OTP: {{otp_code}}", "body": "Dear {{user_name}},\n\nYour security OTP code for transfer of {{amount}} is: {{otp_code}}.\nIt is valid for 5 minutes. Do not share this code."}, "push": {"subject": "Security OTP", "body": "Your OTP for transfer of {{amount}} is {{otp_code}}."}}', 'system'),
  ('tpl-bank-tx-001', 'transaction_alert', 1, 'en', 'transactional', 'active', '["user_name", "amount", "account_no", "tx_id"]', '["sms", "email", "push"]', '{"sms": {"body": "Dear {{user_name}}, {{amount}} debited from account {{account_no}}. TxID: {{tx_id}}. Thank you for your business."}, "email": {"subject": "Debit Notification: {{amount}}", "body": "Dear {{user_name}},\n\nYour account {{account_no}} was debited by {{amount}}.\nTransaction Reference: {{tx_id}}."}, "push": {"subject": "Account Debit", "body": "{{amount}} debited from account {{account_no}}."}}', 'system')
ON CONFLICT (key, version, locale) DO NOTHING;

-- Schema migration safety: Add columns if existing database tables were created with earlier schema versions
ALTER TABLE IF EXISTS audiences ADD COLUMN IF NOT EXISTS source_type VARCHAR(32) NOT NULL DEFAULT 'manual';
ALTER TABLE IF EXISTS audiences ADD COLUMN IF NOT EXISTS filter_query TEXT;
ALTER TABLE IF EXISTS audiences ADD COLUMN IF NOT EXISTS recipients JSONB NOT NULL DEFAULT '[]';
ALTER TABLE IF EXISTS audiences ADD COLUMN IF NOT EXISTS count INT NOT NULL DEFAULT 0;

ALTER TABLE IF EXISTS campaigns ADD COLUMN IF NOT EXISTS channel VARCHAR(32) NOT NULL DEFAULT 'sms';
ALTER TABLE IF EXISTS campaigns ADD COLUMN IF NOT EXISTS template_params JSONB NOT NULL DEFAULT '{}';

-- 12. External Data Sources & DB Connection Registry
CREATE TABLE IF NOT EXISTS datasources (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    driver VARCHAR(32) NOT NULL,
    dsn TEXT NOT NULL,
    host VARCHAR(255),
    port VARCHAR(32),
    username VARCHAR(128),
    db_name VARCHAR(128),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);


