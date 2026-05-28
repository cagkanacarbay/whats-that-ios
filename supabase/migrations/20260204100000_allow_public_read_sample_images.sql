-- Migration: Allow public read access to sample assets (images and voiceovers)
-- The discovery_images and voiceovers bucket policies restrict access to authenticated users.
-- Sample assets are in the "samples/" folder and need to be readable by anyone
-- (including unauthenticated users) for the pre-onboarding flow.

-- Allow public read access to sample images
CREATE POLICY "Anyone can read sample images"
ON storage.objects
FOR SELECT
TO public
USING (
    bucket_id = 'discovery_images'
    AND (storage.foldername(name))[1] = 'samples'
);

-- Allow public read access to sample voiceovers
CREATE POLICY "Anyone can read sample voiceovers"
ON storage.objects
FOR SELECT
TO public
USING (
    bucket_id = 'voiceovers'
    AND (storage.foldername(name))[1] = 'samples'
);
