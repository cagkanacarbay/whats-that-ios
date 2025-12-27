// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from 'npm:@supabase/supabase-js@2';
import { buildCorsHeaders } from '../_shared/cors.ts';
import { createLogger } from '../_shared/logger.ts';
import type { Logger } from '../_shared/logger.ts';

const DISCOVERY_IMAGES_BUCKET = 'discovery_images';
const VOICEOVERS_BUCKET = 'voiceovers';

interface DiscoveryRow {
    id: number;
    image_url: string | null;
}

interface VoiceoverRow {
    discovery_id: number;
    file_name: string | null;
}

serve(async (req: Request) => {
    const origin = req.headers.get('Origin');
    const corsHeaders = buildCorsHeaders(origin);

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: corsHeaders });
    }

    const correlationId = req.headers.get('X-Request-ID') ?? crypto.randomUUID();
    const logger = createLogger({ correlationId, service: 'delete-account' });

    try {
        // Only allow POST requests
        if (req.method !== 'POST') {
            return new Response(
                JSON.stringify({ error: 'Method not allowed' }),
                { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Get authorization header
        const authHeader = req.headers.get('Authorization');
        if (!authHeader?.startsWith('Bearer ')) {
            logger.warn('Missing or invalid Authorization header');
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const jwt = authHeader.replace('Bearer ', '');

        // Create user-level client to verify the JWT
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
        const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
        const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

        const userClient = createClient(supabaseUrl, supabaseAnonKey, {
            global: { headers: { Authorization: `Bearer ${jwt}` } },
            auth: { persistSession: false }
        });

        // Verify the user
        const { data: { user }, error: userError } = await userClient.auth.getUser();
        if (userError || !user) {
            logger.warn('Failed to verify user', { error: userError?.message });
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const userId = user.id;
        logger.info('Starting account deletion', { userId });

        // Create admin client for privileged operations
        const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
            auth: { persistSession: false }
        });

        // Step 1: Fetch user's discoveries to get image paths and discovery IDs
        const { data: discoveries, error: discoveriesError } = await adminClient
            .from('discoveries')
            .select('id, image_url')
            .eq('user_id', userId) as { data: DiscoveryRow[] | null; error: any };

        if (discoveriesError) {
            logger.error('Failed to fetch discoveries', { error: discoveriesError.message });
            throw new Error('Failed to fetch user discoveries');
        }

        const discoveryIds = discoveries?.map(d => d.id) ?? [];
        const imagePaths = discoveries
            ?.filter(d => d.image_url)
            .map(d => d.image_url!) ?? [];

        logger.info('Fetched discoveries', {
            discoveryCount: discoveries?.length ?? 0,
            imageCount: imagePaths.length
        });

        // Step 2: Fetch voiceover file paths for user's discoveries
        let voiceoverPaths: string[] = [];
        if (discoveryIds.length > 0) {
            const { data: voiceovers, error: voiceoversError } = await adminClient
                .from('discovery_voiceovers')
                .select('discovery_id, file_name')
                .in('discovery_id', discoveryIds) as { data: VoiceoverRow[] | null; error: any };

            if (voiceoversError) {
                logger.warn('Failed to fetch voiceovers', { error: voiceoversError.message });
                // Continue anyway - voiceovers are less critical
            } else {
                voiceoverPaths = voiceovers
                    ?.filter(v => v.file_name)
                    .map(v => `${v.discovery_id}/${v.file_name}`) ?? [];

                logger.info('Fetched voiceovers', { voiceoverCount: voiceoverPaths.length });
            }
        }

        // Step 3: Delete discovery images from storage
        if (imagePaths.length > 0) {
            const { error: imageDeleteError } = await adminClient.storage
                .from(DISCOVERY_IMAGES_BUCKET)
                .remove(imagePaths);

            if (imageDeleteError) {
                logger.warn('Failed to delete some discovery images', {
                    error: imageDeleteError.message,
                    attemptedCount: imagePaths.length
                });
                // Continue anyway - database records will be cascade deleted
            } else {
                logger.info('Deleted discovery images', { count: imagePaths.length });
            }
        }

        // Step 4: Delete voiceover files from storage
        if (voiceoverPaths.length > 0) {
            const { error: voiceoverDeleteError } = await adminClient.storage
                .from(VOICEOVERS_BUCKET)
                .remove(voiceoverPaths);

            if (voiceoverDeleteError) {
                logger.warn('Failed to delete some voiceover files', {
                    error: voiceoverDeleteError.message,
                    attemptedCount: voiceoverPaths.length
                });
                // Continue anyway
            } else {
                logger.info('Deleted voiceover files', { count: voiceoverPaths.length });
            }
        }

        // Step 5: Delete the user from auth.users (triggers cascading deletes)
        const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId);

        if (deleteUserError) {
            logger.error('Failed to delete user', { error: deleteUserError.message });
            return new Response(
                JSON.stringify({ error: 'Failed to delete account' }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        logger.info('Account deletion completed successfully', { userId });

        return new Response(
            JSON.stringify({
                success: true,
                deletedImages: imagePaths.length,
                deletedVoiceovers: voiceoverPaths.length
            }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        logger.error('Unexpected error during account deletion', {
            error: error instanceof Error ? error.message : String(error)
        });
        return new Response(
            JSON.stringify({ error: 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
