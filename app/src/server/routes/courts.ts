import { Router } from 'express';
import sql from 'mssql';
import type { AppConfig } from '../config.js';
import { runShared } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import type { AvailableCourt, CourtSearchResponse } from '../../shared/types.js';
import type { SizeType, SurfaceType } from '../../shared/contract.js';

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
 */

/* ------------------------------------------------------------------ */
/* Local wall-clock time representation                               */
/* ------------------------------------------------------------------ */
/**
 * TIME HANDLING DECISION (documented representation):
 *
 * The facility is a local Vietnamese badminton center. Client and server
 * exchange court times as LOCAL WALL-CLOCK values only:
 *   "YYYY-MM-DDTHH:MM:SS"  (no 'Z', no UTC offset)
 *
 * The server parses the wall-clock parts, validates them arithmetically, and
 * passes the SAME wall-clock string straight to SQL Server bound as
 * DATETIME2(0). No JS Date-to-UTC conversion is ever applied, because tedious
 * renders JS Date objects according to its useUTC option and would shift the
 * requested window by the server timezone offset. Binding the raw string keeps
 * the SQL window byte-identical to what the user selected.
 *
 * "Now" is compared at the same wall-clock level using the facility timezone
 * (Asia/Ho_Chi_Minh, fixed UTC+7, no DST) obtained via Intl — no third-party
 * timezone library is needed. This is UX validation only; availability itself
 * is decided by dbo.sp_GetAvailableCourts on SQL Server.
 */

interface WallClock {
  year: number;
  month: number; // 1-12
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const WALL_CLOCK_REGEX = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/;

function daysInMonth(year: number, month: number): number {
  // month here is 1-based; day 0 of the next month = last day of `month`.
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function parseWallClock(value: string): WallClock | null {
  const m = WALL_CLOCK_REGEX.exec(value);
  if (!m) return null;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  const hour = Number(m[4]);
  const minute = Number(m[5]);
  const second = Number(m[6]);
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > daysInMonth(year, month)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return null;
  return { year, month, day, hour, minute, second };
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** Serialize the wall clock back to the string that goes to SQL (DATETIME2(0)). */
function formatWallClock(t: WallClock): string {
  return `${pad2(t.year)}-${pad2(t.month)}-${pad2(t.day)} ${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}`;
}

/** Minutes of the day (0..1439). Only meaningful for intra-day math. */
function minutesOfDay(t: WallClock): number {
  return t.hour * 60 + t.minute;
}

/**
 * Build a Date from wall-clock parts using the LOCAL process timezone.
 * Every comparison here compares two LOCAL Dates, so both share the same
 * timezone offset and the difference is exactly the wall-clock difference —
 * the result is independent of the server's actual timezone.
 */
function toLocalDate(t: WallClock): Date {
  return new Date(t.year, t.month - 1, t.day, t.hour, t.minute, t.second);
}

/** Current wall clock at the facility timezone (Vietnam, fixed UTC+7, no DST). */
function vietnamWallNow(): WallClock {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Ho_Chi_Minh',
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date());
  const pick = (type: Intl.DateTimeFormatPartTypes): number =>
    Number(parts.find((p) => p.type === type)?.value ?? 0);
  return { year: pick('year'), month: pick('month'), day: pick('day'), hour: pick('hour'), minute: pick('minute'), second: pick('second') };
}

/* ------------------------------------------------------------------ */
/* Validation (UX/API only — never weakens DB validation)             */
/* ------------------------------------------------------------------ */

const OPERATING_START_MINUTES = 6 * 60; // 06:00
const OPERATING_END_MINUTES = 22 * 60; // 22:00
const MIN_DURATION_MINUTES = 60;
const MAX_DURATION_MINUTES = 180;

type Validation =
  | { ok: true; start: WallClock; end: WallClock; courtId: string | null; startSql: string; endSql: string }
  | { ok: false; message: string };

function validateSearch(rawStart: unknown, rawEnd: unknown, rawCourtId: unknown): Validation {
  if (typeof rawStart !== 'string' || rawStart.length === 0 || typeof rawEnd !== 'string' || rawEnd.length === 0) {
    return { ok: false, message: 'Vui lòng chọn ngày, giờ bắt đầu và giờ kết thúc.' };
  }

  const start = parseWallClock(rawStart);
  if (!start) return { ok: false, message: 'Thời gian bắt đầu không hợp lệ.' };
  const end = parseWallClock(rawEnd);
  if (!end) return { ok: false, message: 'Thời gian kết thúc không hợp lệ.' };

  // 30-minute resolution: minute must be 00 or 30, second must be 0.
  if (start.minute % 30 !== 0 || start.second !== 0) {
    return { ok: false, message: 'Giờ bắt đầu phải theo bước 30 phút (00 hoặc 30, không kèm giây).' };
  }
  if (end.minute % 30 !== 0 || end.second !== 0) {
    return { ok: false, message: 'Giờ kết thúc phải theo bước 30 phút (00 hoặc 30, không kèm giây).' };
  }

  if (toLocalDate(start).getTime() >= toLocalDate(end).getTime()) {
    return { ok: false, message: 'Giờ kết thúc phải sau giờ bắt đầu.' };
  }

  // Same calendar day, no cross-midnight.
  if (start.year !== end.year || start.month !== end.month || start.day !== end.day) {
    return { ok: false, message: 'Thời gian tìm phải nằm trong cùng một ngày (không được qua đêm).' };
  }

  const duration = minutesOfDay(end) - minutesOfDay(start);
  if (duration < MIN_DURATION_MINUTES) {
    return { ok: false, message: 'Thời lượng tối thiểu là 1 giờ.' };
  }
  if (duration > MAX_DURATION_MINUTES) {
    return { ok: false, message: 'Thời lượng tối đa là 3 giờ.' };
  }

  // Operating window 06:00-22:00.
  if (minutesOfDay(start) < OPERATING_START_MINUTES || minutesOfDay(end) > OPERATING_END_MINUTES) {
    return { ok: false, message: 'Thời gian tìm phải nằm trong khung hoạt động 06:00–22:00.' };
  }

  // Not in the past (wall-clock comparison at the facility timezone).
  const now = vietnamWallNow();
  if (toLocalDate(start).getTime() <= toLocalDate(now).getTime()) {
    return { ok: false, message: 'Khung giờ đã chọn đã trôi qua. Vui lòng chọn thời gian trong tương lai.' };
  }

  // Optional courtId must be a valid GUID when provided.
  let courtId: string | null = null;
  if (rawCourtId !== undefined && rawCourtId !== null && rawCourtId !== '') {
    if (typeof rawCourtId !== 'string' || !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(rawCourtId)) {
      return { ok: false, message: 'Mã sân (courtId) không hợp lệ.' };
    }
    courtId = rawCourtId;
  }

  return { ok: true, start, end, courtId, startSql: formatWallClock(start), endSql: formatWallClock(end) };
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

export function createCourtsRouter(cfg: AppConfig): Router {
  const router = Router();

  router.get('/available', async (req, res) => {
    const validation = validateSearch(req.query.startTime, req.query.endTime, req.query.courtId);
    if (!validation.ok) {
      res.status(400).json({ error: { code: null, message: validation.message } });
      return;
    }
    // Narrowed, plain captures so the async closure keeps the values.
    const { startSql, endSql, courtId } = validation;

    try {
      const rows = await runShared(cfg, async (request) => {
        const r = request.input('StartTime', sql.DateTime2(0), startSql);
        r.input('EndTime', sql.DateTime2(0), endSql);
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
      // Shared pool absent/DB unreachable -> 500; business errors surfaced as-is.
      res.status(mapped.code === 1205 ? 409 : 500).json({ error: toSafeError(mapped) });
    }
  });

  return router;
}