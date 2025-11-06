-- Create push tokens table
CREATE TABLE public.push_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  token VARCHAR(255) NOT NULL,
  platform VARCHAR(20) CHECK (platform IN ('ios', 'android')),
  device_id VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  last_active TIMESTAMPTZ DEFAULT NOW(),
  is_valid BOOLEAN DEFAULT true,
  failed_attempts INTEGER DEFAULT 0,
  UNIQUE(user_id, token)
);

-- Add RLS policies
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own push tokens" ON public.push_tokens
  FOR ALL USING (auth.uid() = user_id);

-- Add indexes for performance
CREATE INDEX idx_push_tokens_user_id ON public.push_tokens(user_id);
CREATE INDEX idx_push_tokens_token ON public.push_tokens(token);
CREATE INDEX idx_push_tokens_last_active ON public.push_tokens(last_active); -- For cleanup queries