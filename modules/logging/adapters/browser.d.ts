export type LogLevel = 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'fatal';
export interface KoraLoggerApi {
    isEnabled(level: LogLevel): boolean;
    trace(event: string, message: string, fields?: Record<string, unknown>): boolean;
    debug(event: string, message: string, fields?: Record<string, unknown>): boolean;
    info(event: string, message: string, fields?: Record<string, unknown>): boolean;
    warn(event: string, message: string, fields?: Record<string, unknown>): boolean;
    error(event: string, message: string, fields?: Record<string, unknown>): boolean;
    fatal(event: string, message: string, fields?: Record<string, unknown>): boolean;
}
declare global { var KoraLogger: KoraLoggerApi; }
