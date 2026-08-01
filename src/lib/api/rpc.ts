import type { SupabaseClient } from '@supabase/supabase-js';

export type RpcEnvelope<T> = {
  success: boolean;
  data: T;
};

export class BackendError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly cause?: unknown
  ) {
    super(message);
  }
}

export async function callRpc<T>(
  client: SupabaseClient,
  functionName: string,
  parameters: Record<string, unknown> = {}
): Promise<T> {
  const { data, error } = await client.rpc(functionName, parameters);
  if (error) {
    throw new BackendError(error.message, error.details || error.message, error);
  }
  const envelope = data as RpcEnvelope<T>;
  if (!envelope?.success) {
    throw new BackendError('INVALID_RESPONSE', `RPC ${functionName} returned an invalid response.`);
  }
  return envelope.data;
}
