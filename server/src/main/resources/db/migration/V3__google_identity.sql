-- Additive identity binding: password accounts remain untouched; Google-only accounts have no password.
ALTER TABLE app_user ALTER COLUMN password_hash DROP NOT NULL;
CREATE TABLE external_identity (
  issuer VARCHAR(64) NOT NULL,
  subject VARCHAR(255) NOT NULL,
  user_id UUID NOT NULL REFERENCES app_user(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (issuer, subject),
  UNIQUE (user_id, issuer)
);
