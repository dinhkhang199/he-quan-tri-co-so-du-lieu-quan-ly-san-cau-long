import { Router } from 'express';
import sql from 'mssql';
import type { AppConfig } from '../config.js';
import { runShared } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { AvailableCourt, CourtSearchResponse } from '../../shared/types.js';
import type { SizeType, SurfaceType } from '../../shared/contract.js';
import { isValidCourtId, toSqlDate, validateWindow, type WallClock } from '../time.js';

/**
 * Public court availability API (Phase 2.3).
 *
 * GET /api/courts/available?startTime=...&endTime=...&courtId=...
 *
 * This is a PUBLIC read for guests and uses the shared (no-session) SQL pool.
 * It NEVER touches SessionDb: an authenticated CUSTOMER that performs a court
 * search keeps their dedicated SESSION_CONTEXT connection untouched. The
 * backend does not query Bookings directly nor does it reproduce overlap logic
 * in JavaScript — dbo.sp_GetAvailableCourts is the single source of
 * availability truth and returns only courts that pass fn_IsCourtAvailable.
 *
 * Wall-clock parsing/validation lives in ../time.ts (shared with bookings.ts).
 * Times are local wall-clock values passed verbatim to SQL as DATETIME2(0).
 */

type Validation =
  | { ok: true; start: WallClock; end: WallClock; courtId: string | null; startSql: string; endSql: string }
  | { ok: false; message: string };

function validateSearch(rawStart: unknown, rawEnd: unknown, rawCourtId: unknown): Validation {
  if (typeof rawStart !== 'string' || rawStart.length === 0 || typeof rawEnd !== 'string' || rawEnd.length === 0) {
    return { ok: false, message: 'Vui lòng chọn ngày, giờ bắt đầu và giờ kết thúc.' };
  }

  const window = validateWindow(rawStart, rawEnd, 'tìm');
  if (!window.ok) return { ok: false, message: window.message };

  // Optional courtId must be a valid GUID when provided.
  let courtId: string | null = null;
  if (rawCourtId !== undefined && rawCourtId !== null && rawCourtId !== '') {
    if (!isValidCourtId(rawCourtId)) {
      return { ok: false, message: 'Mã sân (courtId) không hợp lệ.' };
    }
    courtId = rawCourtId;
  }

  return { ok: true, start: window.start, end: window.end, courtId, startSql: window.startSql, endSql: window.endSql };
}

/* ------------------------------------------------------------------ */
/* Route                                                               */
/* ------------------------------------------------------------------ */

/** Exact row shape returned by dbo.sp_GetAvailableCourts (06_procedures.sql). */
interface AvailableCourtRow {
  CourtId: string;
  CourtName: string;
  Address: string;
  SurfaceType: string;
  SizeType: string;
  PricePerHour: number;
  PricePerThreeHours: number;
  IsAvailable: boolean;
}

function toSafeError(mapped: MappedError): { code: number | null; message: string } {
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

function searchFailureStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409;
  if (mapped.code !== null && [50120, 50121, 50122, 50123, 50124, 50125, 50126].includes(mapped.code)) {
    return 400;
  }
  return 500;
}

export function createCourtsRouter(cfg: AppConfig): Router {
  const router = Router();

  router.get('/available', async (req, res) => {
    const validation = validateSearch(req.query.startTime, req.query.endTime, req.query.courtId);
    if (!validation.ok) {
      res.status(400).json({ error: { code: null, message: validation.message } });
      return;
    }
    const { start, end, courtId, startSql, endSql } = validation;

    try {
      const rows = await runShared(cfg, async (request) => {
        const r = request.input('StartTime', sql.DateTime2(0), toSqlDate(start));
        r.input('EndTime', sql.DateTime2(0), toSqlDate(end));
        if (courtId) {
          r.input('CourtId', sql.UniqueIdentifier, courtId);
        }
        const result = await r.execute('dbo.sp_GetAvailableCourts');
        return result.recordset as AvailableCourtRow[];
      });

      const courts: AvailableCourt[] = rows.map((row) => ({
        CourtId: row.CourtId,
        CourtName: row.CourtName,
        Address: row.Address,
        SurfaceType: row.SurfaceType as SurfaceType,
        SizeType: row.SizeType as SizeType,
        PricePerHour: row.PricePerHour,
        PricePerThreeHours: row.PricePerThreeHours,
        IsAvailable: Boolean(row.IsAvailable),
      }));

      const body: CourtSearchResponse = {
        courts,
        count: courts.length,
        window: {
          startTime: startSql.replace(' ', 'T'),
          endTime: endSql.replace(' ', 'T'),
          courtId,
        },
      };
      res.json(body);
    } catch (err) {
      const mapped = mapSqlError(err);
      res.status(searchFailureStatus(mapped)).json({ error: toSafeError(mapped) });
    }
  });

  return router;
}
