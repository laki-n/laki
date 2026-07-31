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

CREATE TABLE IF NOT EXISTS sent_messages (
    id VARCHAR(36) PRIMARY KEY,
    notification_id VARCHAR(36) NOT NULL,
    channel VARCHAR(32) NOT NULL,
    template_key VARCHAR(128) NOT NULL,
    recipient_ref VARCHAR(255) NOT NULL,
    rendered_subject TEXT,
    rendered_body TEXT NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
