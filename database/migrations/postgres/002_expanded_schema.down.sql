-- Rollback 002_expanded_schema (8 Tables)

DROP TABLE IF EXISTS delivery_events CASCADE;
DROP TABLE IF EXISTS notification_channel_attempts CASCADE;
DROP TABLE IF EXISTS suppression_list CASCADE;
DROP TABLE IF EXISTS user_preferences CASCADE;
DROP TABLE IF EXISTS service_template_grants CASCADE;
DROP TABLE IF EXISTS service_identities CASCADE;
DROP TABLE IF EXISTS campaigns CASCADE;
DROP TABLE IF EXISTS audiences CASCADE;
