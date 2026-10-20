-- Nullable for comments written by a V6 server during an incremental rollout.
ALTER TABLE post_comment ADD COLUMN client_id UUID;
CREATE UNIQUE INDEX post_comment_idempotency_idx ON post_comment(author_id,client_id) WHERE client_id IS NOT NULL;
