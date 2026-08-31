import type { NextFunction, Request, Response } from 'express';
import { mapSqlError } from '../../shared/spError.js';

/**
 * Express error handler: translates SQL errors into stable Vietnamese messages
 * for the UI while keeping technical detail in the server log only. The app
 * must never hang or crash on a DB error.
 */
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const mapped = mapSqlError(err);
  console.error(`[badmintonpro] unhandled request error (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  const businessError = mapped.code !== null && mapped.code >= 50000 && mapped.code <= 51999;
  const conflictError = mapped.code === 1205 || mapped.code === 1222 || mapped.code === 2601 || mapped.code === 2627;
  const status = conflictError ? 409 : businessError ? 400 : 500;
  res.status(status).json({
    error: {
      code: mapped.code,
      message: mapped.message ?? mapped.fallback,
    },
  });
}
