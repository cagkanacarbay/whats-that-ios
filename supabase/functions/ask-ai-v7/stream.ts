import type { Logger } from '../_shared/logger.ts';

const encoder = new TextEncoder();

export interface SSEEmitter {
  stream: ReadableStream<Uint8Array>;
  sendEvent: (event: string, data: unknown) => void;
  sendComment: (comment: string) => void;
  close: () => void;
  abort: (reason?: unknown) => void;
}

function formatData(data: unknown): string[] {
  if (data === undefined || data === null) {
    return ['null'];
  }

  if (typeof data === 'string') {
    return data.split('\n');
  }

  try {
    return [JSON.stringify(data)];
  } catch {
    return [String(data)];
  }
}

export function createSSEStream(logger: Logger): SSEEmitter {
  let controller: ReadableStreamDefaultController<Uint8Array> | null = null;
  let closed = false;
  let aborted = false;

  const stream = new ReadableStream<Uint8Array>({
    start(ctrl) {
      controller = ctrl;
    },
    cancel(reason) {
      aborted = true;
      logger.warn('SSE stream cancelled', { reason });
    },
  });

  const safeEnqueue = (payload: string) => {
    if (!controller || closed || aborted) return;
    try {
      controller.enqueue(encoder.encode(payload));
    } catch (error) {
      aborted = true;
      logger.warn('SSE enqueue failed', { error });
    }
  };

  const sendEvent = (event: string, data: unknown) => {
    if (closed || aborted) return;
    safeEnqueue(`event: ${event}\n`);
    for (const line of formatData(data)) {
      safeEnqueue(`data: ${line}\n`);
    }
    safeEnqueue('\n');
  };

  const sendComment = (comment: string) => {
    if (closed || aborted) return;
    safeEnqueue(`: ${comment}\n\n`);
  };

  const close = () => {
    if (!controller || closed || aborted) return;
    try {
      controller.enqueue(encoder.encode('event: end\n'));
      controller.enqueue(encoder.encode('data: {}\n\n'));
      controller.close();
      closed = true;
    } catch (error) {
      aborted = true;
      logger.warn('SSE close failed', { error });
    } finally {
      controller = null;
    }
  };

  const abort = (reason?: unknown) => {
    if (!controller || aborted) return;
    aborted = true;
    logger.warn('SSE abort invoked', { reason });
    try {
      controller.error(reason ?? new Error('SSE aborted'));
    } catch (error) {
      logger.warn('SSE controller.error failed', { error });
    } finally {
      controller = null;
    }
  };

  return {
    stream,
    sendEvent,
    sendComment,
    close,
    abort,
  };
}
