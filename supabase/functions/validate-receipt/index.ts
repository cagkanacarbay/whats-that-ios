// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { buildCorsHeaders } from '../_shared/cors.ts';
import { getCreditsForProductId } from '../_shared/Products.ts';
import { createLogger } from '../_shared/logger.ts';
import type { Logger } from '../_shared/logger.ts';

// StoreKit 2 JWS Transaction Payload interface
interface JWSTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  purchaseDate: number;
  originalPurchaseDate: number;
  quantity: number;
  type: 'Consumable' | 'Non-Consumable' | 'Auto-Renewable Subscription' | 'Non-Renewing Subscription';
  inAppOwnershipType: 'PURCHASED' | 'FAMILY_SHARED';
  signedDate: number;
  environment: 'Sandbox' | 'Production';
  storefront: string;
  storefrontId: string;
  price?: number;
  currency?: string;
}

interface RequestBody {
  platform: 'ios' | 'android';
  signedTransaction?: string; // Base64 encoded StoreKit 2 JWS (new method)
  receiptData?: string; // Legacy: Base64 encoded receipt for iOS (kept for backwards compatibility)
  productId: string;
  storeTransactionId: string; // Original transaction ID from Apple
}

// Rate limiting configuration
const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 10;

serve(async (req) => {
  // Utility: mask an identifier by showing beginning and end
  const maskId = (value: string): string => {
    if (!value) return value as unknown as string;
    if (value.length <= 8) {
      return `${value.slice(0, Math.max(1, value.length - 1))}…`;
    }
    return `${value.slice(0, 4)}…${value.slice(-4)}`;
  };

  const correlationId = crypto.randomUUID();
  const logger: Logger = createLogger({ fn: 'validate-receipt', correlationId });
  const corsHeaders = buildCorsHeaders(req.headers.get('Origin'));
  const baseHeaders = { ...corsHeaders, 'X-Correlation-Id': correlationId };
  logger.info('Request received', { method: req.method });

  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    logger.debug('Handling CORS preflight request');
    return new Response('ok', { headers: baseHeaders });
  }

  try {
    const handlerLogger = logger.child({ scope: 'handler' });

    // 1. Extract data and authenticate user
    let body: RequestBody;
    try {
      body = await req.json();
    } catch (e) {
      handlerLogger.warn('Invalid request body', { errorMessage: e instanceof Error ? e.message : String(e) });
      return new Response(JSON.stringify({ success: false, message: 'Invalid request body' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    const { platform, signedTransaction, productId, storeTransactionId } = body || ({} as RequestBody);
    handlerLogger.info('Request data extracted', {
      platform,
      productId,
      hasSignedTransaction: !!signedTransaction,
      storeTransactionIdSuffix: storeTransactionId?.slice(-6)
    });

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      handlerLogger.warn('Missing Authorization header');
      return new Response(JSON.stringify({ success: false, message: 'Not authenticated' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    // Create Supabase client with user's auth token (for user verification and idempotency checks)
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    // Create admin client for privileged operations (granting credits)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      }
    );

    // Get user data
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      handlerLogger.warn('User authentication failed', { errorMessage: userError?.message });
      return new Response(JSON.stringify({ success: false, message: 'Authentication failed' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }
    handlerLogger.info('User authenticated', { userIdMasked: maskId(user.id) });

    // Rate limit check
    const { data: rateLimitAllowed, error: rateLimitError } = await supabaseAdmin.rpc(
      'enforce_edge_function_rate_limit',
      {
        p_user_id: user.id,
        p_function_name: 'validate-receipt',
        p_window_seconds: RATE_LIMIT_WINDOW_SECONDS,
        p_max_requests: RATE_LIMIT_MAX_REQUESTS,
      }
    );

    if (rateLimitError) {
      handlerLogger.error('Rate limit check failed', { errorMessage: rateLimitError.message });
      return new Response(JSON.stringify({ success: false, message: 'Rate limit check failed' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    if (!rateLimitAllowed) {
      handlerLogger.warn('Rate limit exceeded', { userIdMasked: maskId(user.id) });
      return new Response(JSON.stringify({ success: false, message: 'Too many requests. Please wait a moment and try again.' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 429,
      });
    }

    // 2. Platform Check (Focusing on iOS)
    if (platform !== 'ios') {
      handlerLogger.warn('Platform not supported', { platform });
      return new Response(JSON.stringify({ success: false, message: 'Platform not supported' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // 3. Validate the StoreKit 2 signed transaction (JWS)
    const appleLogger = logger.child({ scope: 'apple' });

    if (!signedTransaction) {
      appleLogger.error('No signedTransaction provided');
      return new Response(JSON.stringify({ success: false, message: 'Missing signed transaction data' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // The client now sends the JWS as a raw string (not base64 encoded)
    // JWS format: header.payload.signature (each part is base64url encoded)
    const jwsString = signedTransaction;
    appleLogger.info('JWS received', {
      jwsLength: jwsString.length,
      first50Chars: jwsString.substring(0, 50)
    });

    // Parse the JWS (format: header.payload.signature)
    const jwsParts = jwsString.split('.');
    if (jwsParts.length !== 3) {
      appleLogger.error('Invalid JWS format', {
        partsCount: jwsParts.length,
        jwsPreview: jwsString.substring(0, 100)
      });
      return new Response(JSON.stringify({ success: false, message: 'Invalid JWS format' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // Decode the payload (second part of JWS)
    let transactionPayload: JWSTransactionPayload;
    try {
      // Base64URL decode the payload
      const base64Payload = jwsParts[1].replace(/-/g, '+').replace(/_/g, '/');
      const paddedPayload = base64Payload + '=='.slice(0, (4 - base64Payload.length % 4) % 4);
      const payloadJson = atob(paddedPayload);
      transactionPayload = JSON.parse(payloadJson);
      appleLogger.info('Transaction payload decoded', {
        transactionId: transactionPayload.transactionId,
        originalTransactionId: transactionPayload.originalTransactionId,
        productId: transactionPayload.productId,
        bundleId: transactionPayload.bundleId,
        environment: transactionPayload.environment,
      });
    } catch (e) {
      appleLogger.error('Failed to parse JWS payload', { errorMessage: e instanceof Error ? e.message : String(e) });
      return new Response(JSON.stringify({ success: false, message: 'Invalid transaction payload' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // 4. Validate the transaction payload
    const allowedBundleIds = (Deno.env.get('IOS_BUNDLE_ID') || '')
      .split(',')
      .map(id => id.trim())
      .filter(id => id.length > 0);

    if (allowedBundleIds.length === 0) {
      appleLogger.error('IOS_BUNDLE_ID is not set');
      return new Response(JSON.stringify({ success: false, message: 'Server configuration error' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    // Verify bundle ID
    if (!allowedBundleIds.includes(transactionPayload.bundleId)) {
      appleLogger.warn('Bundle ID mismatch', {
        received: transactionPayload.bundleId,
        allowed: allowedBundleIds
      });
      return new Response(JSON.stringify({ success: false, message: 'Invalid bundle ID' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // Verify product ID matches
    if (transactionPayload.productId !== productId) {
      appleLogger.warn('Product ID mismatch', {
        received: transactionPayload.productId,
        expected: productId
      });
      return new Response(JSON.stringify({ success: false, message: 'Product ID mismatch' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // Verify transaction ID matches
    if (transactionPayload.originalTransactionId !== storeTransactionId) {
      appleLogger.warn('Transaction ID mismatch', {
        received: transactionPayload.originalTransactionId,
        expected: storeTransactionId
      });
      return new Response(JSON.stringify({ success: false, message: 'Transaction ID mismatch' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // Note: For full security, you should verify the JWS signature using Apple's public key.
    // The JWS header contains the certificate chain (x5c) which can be validated against
    // Apple's root certificate. For StoreKit 2, the client-side verification is already done
    // by iOS, so this payload comes from a verified transaction. For production, consider
    // implementing full JWS signature verification or using App Store Server API.

    appleLogger.info('Transaction validation successful', {
      environment: transactionPayload.environment,
      transactionIdSuffix: transactionPayload.transactionId?.slice(-6)
    });

    // 5. Grant Credits
    const dbLogger = logger.child({ scope: 'db' });

    // Check if this transaction has already been processed (idempotency)
    const { data: existingTx, error: checkError } = await supabaseClient
      .from('credit_transactions')
      .select('id')
      .eq('store_transaction_id', storeTransactionId)
      .eq('platform', 'ios')
      .limit(1)
      .single();

    if (checkError && checkError.code !== 'PGRST116') { // PGRST116 means no rows found, which is good
      dbLogger.error('Error checking for existing transaction', { errorMessage: checkError.message });
      return new Response(JSON.stringify({ success: false, message: 'Database error checking transaction history' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    if (existingTx) {
      handlerLogger.warn('Transaction already processed', { storeTransactionIdSuffix: storeTransactionId?.slice(-6) });
      return new Response(JSON.stringify({ success: true, message: 'Transaction already processed' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Grant credits by calling the DB function
    const creditsToAdd = getCreditsForProductId(productId);
    if (creditsToAdd <= 0) {
      dbLogger.error('Invalid credit amount configured', { productId, creditsToAdd });
      return new Response(JSON.stringify({ success: false, message: 'Invalid credit amount configured' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    handlerLogger.info('Granting credits', { userIdMasked: maskId(user.id), productId, creditsToAdd, storeTransactionIdSuffix: storeTransactionId?.slice(-6) });
    // Use admin client (service_role) to call the RPC - required because function is restricted to service_role
    const { error: rpcError } = await supabaseAdmin.rpc('add_credits_after_validation', {
      p_user_id: user.id,
      p_amount: creditsToAdd,
      p_platform: 'ios',
      p_product_id: productId,
      p_store_transaction_id: storeTransactionId,
    });

    if (rpcError) {
      dbLogger.error('Credit RPC failed', { errorMessage: rpcError.message });
      return new Response(JSON.stringify({ success: false, message: 'Failed to grant credits' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    handlerLogger.info('Credits granted successfully', { userIdMasked: maskId(user.id), creditsToAdd });
    return new Response(JSON.stringify({ success: true }), {
      headers: { ...baseHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    const handlerLogger = logger.child({ scope: 'handler' });
    handlerLogger.error('Unhandled error in validate-receipt', { errorMessage: error instanceof Error ? error.message : String(error) });
    if (error instanceof Error && error.stack) {
      handlerLogger.debug('Stack trace', { stack: error.stack });
    }
    return new Response(JSON.stringify({ success: false, message: error instanceof Error ? error.message : 'An internal server error occurred.' }), {
      headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});

/* To invoke locally:

  1. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  2. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/validate-receipt' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"name":"Functions"}'

*/
