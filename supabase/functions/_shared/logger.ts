export interface LoggerContext {
  correlationId?: string;
  fn?: string;
  scope?: string;
}

export interface Logger {
  debug(message: string, meta?: Record<string, unknown>): void;
  info(message: string, meta?: Record<string, unknown>): void;
  warn(message: string, meta?: Record<string, unknown>): void;
  error(message: string, meta?: Record<string, unknown>): void;
  child(context: Partial<LoggerContext>): Logger;
}

// --- Environment & Log Level ---
const environment = Deno.env.get('DENO_ENV') ?? 'development';
const isProduction = environment === 'production';

type LogLevel = 'debug' | 'info' | 'warn' | 'error' | 'silent';
const LEVELS: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
  silent: 50,
};

const normalizeLevel = (value?: string | null): LogLevel | null => {
  if (!value) return null;
  const v = value.toLowerCase().trim();
  if (v in LEVELS) return v as LogLevel;
  if (v === 'warning') return 'warn';
  return null;
};

const DEFAULT_LOG_LEVEL: LogLevel = isProduction ? 'info' : 'debug';
const CONFIGURED_LOG_LEVEL: LogLevel = normalizeLevel(Deno.env.get('LOG_LEVEL')) || DEFAULT_LOG_LEVEL;

const shouldEmit = (level: 'debug' | 'info' | 'warn' | 'error'): boolean => {
  return LEVELS[level] >= LEVELS[CONFIGURED_LOG_LEVEL];
};

const SENSITIVE_STRING_KEYS = [
  /token/i,
  /secret/i,
  /receipt/i,
  /password/i,
  /base64/i,
  /body/i,
  /payload/i,
  /chunk/i,
  /description/i,
  /analysis/i,
  /metadata/i,
  /image/i,
];

const ID_KEYS = [/user.?id/i, /discovery.?id/i, /session.?id/i];

const LAT_KEYS = [/lat/i];
const LON_KEYS = [/lon/i, /long/i];

const maskId = (value: string) => {
  if (!value) return value;
  if (value.length <= 8) {
    return `${value.slice(0, Math.max(1, value.length - 1))}…`;
  }
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
};

const truncateString = (value: string) => {
  if (value.length <= 200) {
    return value;
  }
  return `${value.slice(0, 100)}…[${value.length} chars]`;
};

const sanitizeValue = (key: string, value: unknown): unknown => {
  if (!isProduction) {
    return value;
  }

  if (value === null || value === undefined) {
    return value;
  }

  if (typeof value === 'number') {
    if (LAT_KEYS.some(pattern => pattern.test(key))) {
      return Number(value.toFixed(2));
    }
    if (LON_KEYS.some(pattern => pattern.test(key))) {
      return Number(value.toFixed(2));
    }
    return value;
  }

  if (typeof value === 'string') {
    if (SENSITIVE_STRING_KEYS.some(pattern => pattern.test(key))) {
      return `[redacted length=${value.length}]`;
    }
    if (ID_KEYS.some(pattern => pattern.test(key))) {
      return maskId(value);
    }
    return truncateString(value);
  }

  if (Array.isArray(value)) {
    return value.map((entry, index) => sanitizeValue(`${key}[${index}]`, entry));
  }

  if (typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [entryKey, entryValue] of Object.entries(value as Record<string, unknown>)) {
      result[entryKey] = sanitizeValue(entryKey, entryValue);
    }
    return result;
  }

  return value;
};

const sanitizeMeta = (meta?: Record<string, unknown>) => {
  if (!meta) {
    return undefined;
  }
  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(meta)) {
    sanitized[key] = sanitizeValue(key, value);
  }
  return sanitized;
};

const buildLogger = (context: LoggerContext, startTime: number): Logger => {
  const emit = (level: 'debug' | 'info' | 'warn' | 'error', message: string, meta?: Record<string, unknown>) => {
    if (!shouldEmit(level)) return;
    const sanitizedMeta = sanitizeMeta(meta);

    const prefix = context.correlationId ? `[cid=${context.correlationId}] ` : '';

    const metaEntries = sanitizedMeta
      ? Object.entries(sanitizedMeta).map(([key, value]) =>
          typeof value === 'object' && value !== null ? `${key}=${JSON.stringify(value)}` : `${key}=${value}`
        )
      : [];

    const line = `${prefix}${message}` + (metaEntries.length ? ` | ${metaEntries.join(' ')}` : '');

    const method = level === 'error' ? console.error : level === 'warn' ? console.warn : level === 'debug' ? console.debug : console.log;
    method(line);
  };

  return {
    debug: (message, meta) => emit('debug', message, meta),
    info: (message, meta) => emit('info', message, meta),
    warn: (message, meta) => emit('warn', message, meta),
    error: (message, meta) => emit('error', message, meta),
    child: (childContext: Partial<LoggerContext>) =>
      buildLogger({ ...context, ...childContext }, startTime),
  };
};

export const createLogger = (context: LoggerContext): Logger => {
  const correlationId = context.correlationId ?? crypto.randomUUID();
  const initialContext: LoggerContext = {
    ...context,
    correlationId,
  };
  const startTime = Date.now();
  return buildLogger(initialContext, startTime);
};

