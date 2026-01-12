import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
    // Handle CORS preflight
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        // Create admin client with service role
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

        const supabase = createClient(supabaseUrl, serviceRoleKey, {
            auth: { persistSession: false },
        });

        // Fetch discoveries for gemini-3-flash-preview model
        const { data: discoveries, error: dbError } = await supabase
            .from("discoveries")
            .select("id, title, short_description, description, image_url, country, locality, street_name, closest_place, created_at")
            .eq("model", "gemini-3-flash-preview")
            .order("id", { ascending: true });

        if (dbError) {
            throw new Error(`Database error: ${dbError.message}`);
        }

        // Generate signed URLs for each discovery's image
        const results = await Promise.all(
            (discoveries || []).map(async (discovery) => {
                let signedImageUrl: string | null = null;

                if (discovery.image_url) {
                    const { data: signedData, error: signError } = await supabase.storage
                        .from("discovery_images")
                        .createSignedUrl(discovery.image_url, 3600); // 1 hour expiry

                    if (!signError && signedData) {
                        signedImageUrl = signedData.signedUrl;
                    }
                }

                return {
                    ...discovery,
                    signed_image_url: signedImageUrl,
                };
            })
        );

        return new Response(JSON.stringify(results), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    } catch (error) {
        console.error("Export error:", error);
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
});
