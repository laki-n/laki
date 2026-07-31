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

ALTER TABLE audiences ADD COLUMN IF NOT EXISTS source_type VARCHAR(32) NOT NULL DEFAULT 'manual';
ALTER TABLE audiences ADD COLUMN IF NOT EXISTS filter_query TEXT;
ALTER TABLE audiences ADD COLUMN IF NOT EXISTS recipients JSONB NOT NULL DEFAULT '[]';
ALTER TABLE audiences ADD COLUMN IF NOT EXISTS count INT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS campaigns (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    template_key VARCHAR(128) NOT NULL,
    channel VARCHAR(32) NOT NULL DEFAULT 'sms',
    audience_id VARCHAR(36) NOT NULL REFERENCES audiences(id) ON DELETE CASCADE,
    template_params JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    max_per_minute INT NOT NULL DEFAULT 1000,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS channel VARCHAR(32) NOT NULL DEFAULT 'sms';
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS template_params JSONB NOT NULL DEFAULT '{}';

CREATE TABLE IF NOT EXISTS service_identities (
    id VARCHAR(36) PRIMARY KEY,
    service_name VARCHAR(128) UNIQUE NOT NULL,
    api_key_hash VARCHAR(255) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS service_template_grants (
    id VARCHAR(36) PRIMARY KEY,
    service_name VARCHAR(128) NOT NULL REFERENCES service_identities(service_name) ON DELETE CASCADE,
    template_key VARCHAR(128) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uk_service_template UNIQUE (service_name, template_key)
);

CREATE TABLE IF NOT EXISTS user_preferences (
    user_id VARCHAR(128) PRIMARY KEY,
    email_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    sms_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    push_opt_out BOOLEAN NOT NULL DEFAULT FALSE,
    category_opt_outs JSONB NOT NULL DEFAULT '{}',
    preferred_language VARCHAR(16) DEFAULT 'en',
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS suppression_list (
    id VARCHAR(36) PRIMARY KEY,
    recipient_ref VARCHAR(255) UNIQUE NOT NULL,
    reason VARCHAR(128) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_channel_attempts (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    channel VARCHAR(32) NOT NULL,
    attempt_number INT NOT NULL DEFAULT 1,
    provider VARCHAR(64) NOT NULL,
    provider_message_id VARCHAR(255),
    status VARCHAR(32) NOT NULL,
    error_reason TEXT,
    attempted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS delivery_events (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) REFERENCES notifications(id) ON DELETE SET NULL,
    provider VARCHAR(64) NOT NULL,
    provider_message_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    raw_payload JSONB NOT NULL DEFAULT '{}',
    received_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
