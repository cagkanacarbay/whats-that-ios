// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { buildCorsHeaders } from '../_shared/cors.ts';
import { getCreditsForProductId } from '../_shared/Products.ts';
import { createLogger } from '../_shared/logger.ts';
import type { Logger } from '../_shared/logger.ts';

// Apple verification endpoints
const APPLE_PRODUCTION_URL = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_SANDBOX_URL = 'https://sandbox.itunes.apple.com/verifyReceipt';

interface RequestBody {
  platform: 'ios' | 'android';
  receiptData: string; // Base64 encoded receipt for iOS
  productId: string;
  storeTransactionId: string; // Original transaction ID from Apple
}

interface AppleReceiptResponse {
  status: number;
  environment?: 'Sandbox' | 'Production';
  receipt?: {
    in_app: AppleInAppPurchase[];
    bundle_id: string;
    // other fields...
  };
  'is-retryable'?: boolean;
  latest_receipt_info?: AppleInAppPurchase[]; // Used for auto-renewables, might contain original consumable info
  pending_renewal_info?: any[]; // For subscriptions
}

interface AppleInAppPurchase {
  quantity: string;
  product_id: string;
  transaction_id: string; // Current transaction ID
  original_transaction_id: string; // Original transaction ID (important for consumables)
  purchase_date_ms: string;
  // other fields...
}

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
    const { platform, receiptData, productId, storeTransactionId } = body || ({} as RequestBody);
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      handlerLogger.warn('Missing Authorization header');
      return new Response(JSON.stringify({ success: false, message: 'Not authenticated' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    // Create Supabase client with user's auth token
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
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

    // 2. Platform Check (Focusing on iOS)
    if (platform !== 'ios') {
      handlerLogger.warn('Platform not supported', { platform });
      return new Response(JSON.stringify({ success: false, message: 'Platform not supported' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    // 3. Prepare for Apple Validation
    const appleLogger = logger.child({ scope: 'apple' });
    const appleSharedSecret = Deno.env.get('APPLE_SHARED_SECRET');
    if (!appleSharedSecret) {
      appleLogger.error('APPLE_SHARED_SECRET is not set');
      return new Response(JSON.stringify({ success: false, message: 'Server configuration error' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    const requestBody = JSON.stringify({
      'receipt-data': receiptData,
      'password': appleSharedSecret,
      'exclude-old-transactions': false // Recommended to include all transactions for validation context
    });

    // 4. Attempt Validation (Try Production first, then Sandbox on specific error)
    let appleResponse: AppleReceiptResponse | null = null;
    let isValid = false;
    let isSandbox = false;

    let validationUrl = APPLE_PRODUCTION_URL;

    try {
      appleLogger.info('Attempting Apple production validation');
      const prodRes = await fetch(validationUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: requestBody,
      });
      appleResponse = await prodRes.json();
      appleLogger.info('Apple production response received', { status: appleResponse?.status });

      // Check for sandbox status code
      if (appleResponse?.status === 21007) {
        appleLogger.info('Receipt from sandbox, retrying with sandbox URL');
        validationUrl = APPLE_SANDBOX_URL;
        isSandbox = true;
        const sandboxRes = await fetch(validationUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: requestBody,
        });
        appleResponse = await sandboxRes.json();
        appleLogger.info('Apple sandbox response received', { status: appleResponse?.status });
      }

      // Check for successful status (0) and matching bundle ID
      const expectedBundleId = Deno.env.get('IOS_BUNDLE_ID');
      if (!expectedBundleId) {
          appleLogger.error('IOS_BUNDLE_ID is not set');
          return new Response(JSON.stringify({ success: false, message: 'Server configuration error' }), {
            headers: { ...baseHeaders, 'Content-Type': 'application/json' },
            status: 500,
          });
      }

      if (appleResponse?.status === 0 && appleResponse.receipt?.bundle_id === expectedBundleId) {
         // Find the specific transaction within the receipt
         // Check both `in_app` (older style) and `latest_receipt_info` (newer style/subscriptions)
         const allPurchases = [
           ...(appleResponse.receipt?.in_app || []),
           ...(appleResponse.latest_receipt_info || [])
         ];

         const relevantPurchase = allPurchases.find(p =>
             p.product_id === productId &&
             p.original_transaction_id === storeTransactionId // Match original ID for consumables
         );

         if (relevantPurchase) {
             appleLogger.info('Matching purchase found', { productId, storeTransactionIdSuffix: storeTransactionId?.slice(-6) });
             isValid = true;
         } else {
             appleLogger.warn('Receipt valid but transaction not found', { productId, storeTransactionIdSuffix: storeTransactionId?.slice(-6) });
         }

      } else {
        appleLogger.warn('Apple validation failed', { status: appleResponse?.status, responseBundleId: appleResponse?.receipt?.bundle_id, expectedBundleId });
      }

    } catch (fetchError) {
      appleLogger.error('Error communicating with Apple', { errorMessage: fetchError instanceof Error ? fetchError.message : String(fetchError) });
      return new Response(JSON.stringify({ success: false, message: 'Failed to communicate with Apple servers' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 502,
      });
    }

    // 5. Grant Credits if Valid
    if (isValid) {
      const dbLogger = logger.child({ scope: 'db' });
      appleLogger.info('Receipt validation successful', { sandbox: isSandbox });

      // Check if this transaction has already been processed (idempotency)
      const { data: existingTx, error: checkError } = await supabaseClient
        .from('credit_transactions')
        .select('id')
        .eq('store_transaction_id', storeTransactionId)
        .eq('platform', 'ios')
        .limit(1)
        .single(); // Use single() to get null if not found, or the row if found

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
      const { error: rpcError } = await supabaseClient.rpc('add_credits_after_validation', {
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

    } else {
      // Validation failed
      appleLogger.info('Receipt validation failed', { status: appleResponse?.status, sandbox: isSandbox });
      return new Response(JSON.stringify({ success: false, message: 'Invalid receipt or transaction not found' }), {
        headers: { ...baseHeaders, 'Content-Type': 'application/json' },
        status: 400, // Bad request (invalid receipt)
      });
    }

  } catch (error) {
    const handlerLogger = logger.child({ scope: 'handler' });
    handlerLogger.error('Unhandled error in validate-receipt', { errorMessage: error instanceof Error ? error.message : String(error) });
    if (error instanceof Error && error.stack) {
      handlerLogger.debug('Stack trace', { stack: error.stack });
    }
    return new Response(JSON.stringify({ success: false, message: error instanceof Error ? error.message : 'An internal server error occurred.' }), {
      headers: { ...baseHeaders, 'Content-Type': 'application/json' },
      status: 500, // Internal server error
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
