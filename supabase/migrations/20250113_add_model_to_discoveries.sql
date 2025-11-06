-- Add model column to discoveries table to track which AI model was used
ALTER TABLE discoveries 
ADD COLUMN model TEXT;

-- Set default value for existing records (assuming they used Claude 3.5 Sonnet)
UPDATE discoveries 
SET model = 'claude-3-5-sonnet-20241022' 
WHERE model IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN discoveries.model IS 'The AI model used to generate this discovery (e.g., gpt-4.1, claude-opus-4-1-20250805)';