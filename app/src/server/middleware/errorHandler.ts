import type { NextFunction, Request, Response } from 'express';
import { mapSqlError } from '../../shared/spError.js';

/**
 * Express error handler: translates SQL errors into stable Vietnamese messages
 * for the UI while keeping technical detail for logs/dev mode. The app must
 * never hang or crash on a DB error.
 */
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const mapped = mapSqlError(err);
  const status = mapped.code === 1205 ? 409 : 400;
  res.status(status).json({
    error: {
      code: mapped.code,
      message: mapped.message ?? mapped.fallback,
      technical: process.env.NODE_ENV === 'test' || process.env.NODE_ENV === 'production' ? undefined : mapped.technical,
    },
  });
}