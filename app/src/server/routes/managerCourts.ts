import { Router } from 'express';
import sql from 'mssql';
import type { SessionDb } from '../db/index.js';
import { mapSqlError } from '../../shared/spError.js';
import type { MappedError } from '../../shared/spError.js';
import { isValidGuid } from '../time.js';
import { SIZE_TYPES, SURFACE_TYPES } from '../../shared/contract.js';
import type {
  ManagerCourt,
  ManagerCourtCreateResponse,
  ManagerCourtMutationResponse,
  ManagerCourtsResponse,
} from '../../shared/types.js';

/**
 * Manager / Court Manager court-management API (Phase 2.7) —
 * authenticated MANAGER / COURT_MANAGER only.
 *
 * GET  /api/manager/courts                    list (active + inactive)
 * POST /api/manager/courts                    create   -> dbo.sp_CreateCourt
 * PUT  /api/manager/courts/:courtId           update   -> dbo.sp_UpdateCourt
 * POST /api/manager/courts/:courtId/deactivate soft deactivation -> dbo.sp_DeactivateCourt
 *
 * Every route runs on the authenticated SESSION_CONTEXT connection (SessionDb)
 * AFTER verifySessionContext(sessionId, userId, role):
 *   - the court list is a FIXED SELECT from dbo.Courts whose WHERE uses
 *     SESSION_CONTEXT(N'Role')/SESSION_CONTEXT(N'UserId') IN SQL, so
 *     COURT_MANAGER rows are scoped to `OwnerId = actor` BEFORE they leave SQL
 *     Server and MANAGER sees every court (including IsActive = 0);
 *   - every mutation executes the matching contract Stored Procedure, which
 *     re-validates role, SESSION_CONTEXT and (for COURT_MANAGER) ownership
 *     under lock inside the procedure.
 *
 * The request never carries UserId/Role/OwnerId; ownership is derived by the
 * Stored Procedures from the authenticated session (sp_CreateCourt defaults
 * @OwnerId to the session user and forces COURT_MANAGER to self). The only
 * client inputs are the editable court fields + the validated :courtId route
 * parameter. Authorization truth is the SQL SESSION_CONTEXT + the procedures —
 * never the browser.
 */

/** Serialize a failure for the HTTP client: code + safe Vietnamese message ONLY. */
function serializeError(mapped: MappedError) {
  console.error(`[managerCourts] request failed (code=${mapped.code ?? 'none'}): ${mapped.technical}`);
  return {
    code: mapped.code,
    message: mapped.message ?? mapped.fallback,
  };
}

/**
 * Safe HTTP status for a court mutation failure (exact THROW codes from
 * 06_procedures.sql). The SP-specific actor/session codes (50070/50080/50090)
 * are handled by the routes as 401 + session clear, because the route already
 * gated role — if they fire, the web identity is out of sync with SQL.
 */
function courtMutationStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // deadlock victim: safe manual retry
  if (mapped.code === 50081 || mapped.code === 50091) return 404; // court not found
  if (mapped.code === 50071 || mapped.code === 50082 || mapped.code === 50092) return 403; // ownership / self-only
  if (mapped.code === 50072 || mapped.code === 50083) return 400; // price must be > 0
  return 500;
}

/** Safe HTTP status for the court-list read (a base-table SELECT, not an SP THROW). */
function courtListStatus(mapped: MappedError): number {
  if (mapped.code === 1205) return 409; // read deadlock victim: safe retry
  return 500;
}

interface ValidatedCourtInput {
  courtName: string;
  address: string;
  surfaceType: string;
  sizeType: string;
  pricePerHour: number;
  pricePerThreeHours: number;
  imageUrl: string | null;
}

/** UX-level shape validation; dbo.sp_CreateCourt/sp_UpdateCourt stay authoritative. */
function validateCourtInput(body: unknown):
  | { ok: true; input: ValidatedCourtInput }
  | { ok: false; message: string } {
  const b = (body ?? {}) as Record<string, unknown>;

  const courtName = typeof b.courtName === 'string' ? b.courtName.trim() : '';
  if (courtName.length === 0 || courtName.length > 100) {
    return { ok: false, message: 'Tên sân phải từ 1 đến 100 ký tự.' };
  }

  const address = typeof b.address === 'string' ? b.address.trim() : '';
  if (address.length === 0 || address.length > 255) {
    return { ok: false, message: 'Địa chỉ phải từ 1 đến 255 ký tự.' };
  }

  const surfaceType = typeof b.surfaceType === 'string' ? b.surfaceType : '';
  if (!(SURFACE_TYPES as readonly string[]).includes(surfaceType)) {
    return { ok: false, message: 'Loại mặt sân không hợp lệ.' };
  }

  const sizeType = typeof b.sizeType === 'string' ? b.sizeType : '';
  if (!(SIZE_TYPES as readonly string[]).includes(sizeType)) {
    return { ok: false, message: 'Kích thước sân không hợp lệ.' };
  }

  const pricePerHour = b.pricePerHour;
  if (typeof pricePerHour !== 'number' || !Number.isFinite(pricePerHour)) {
    return { ok: false, message: 'Giá 1 giờ không hợp lệ.' };
  }
  const pricePerThreeHours = b.pricePerThreeHours;
  if (typeof pricePerThreeHours !== 'number' || !Number.isFinite(pricePerThreeHours)) {
    return { ok: false, message: 'Giá 3 giờ không hợp lệ.' };
  }
  // DECIMAL(12,0): 1..999,999,999,999. The SP re-checks > 0.
  const MAX_PRICE = 999_999_999_999;
  if (pricePerHour <= 0 || pricePerHour > MAX_PRICE) {
    return { ok: false, message: 'Giá sân phải lớn hơn 0.' };
  }
  if (pricePerThreeHours <= 0 || pricePerThreeHours > MAX_PRICE) {
    return { ok: false, message: 'Giá 3 giờ phải lớn hơn 0.' };
  }

  let imageUrl: string | null = null;
  if (b.imageUrl != null) {
    if (typeof b.imageUrl !== 'string') {
      return { ok: false, message: 'Ảnh sân (URL) không hợp lệ.' };
    }
    const trimmed = b.imageUrl.trim();
    if (trimmed.length > 500) {
      return { ok: false, message: 'Ảnh sân (URL) quá dài (tối đa 500 ký tự).' };
    }
    imageUrl = trimmed.length === 0 ? null : trimmed;
  }

  return {
    ok: true,
    input: {
      courtName,
      address,
      surfaceType,
      sizeType,
      pricePerHour: Math.trunc(pricePerHour),
      pricePerThreeHours: Math.trunc(pricePerThreeHours),
      imageUrl,
    },
  };
}

export function createManagerCourtsRouter(sessionDb: SessionDb): Router {
  const router = Router();

  /**
   * GET /api/manager/courts — authenticated manager court list (Phase 2.7).
   *
   * The scope is NOT applied in Node/React — it is applied in the SQL WHERE
   * clause using SESSION_CONTEXT on the authenticated session connection:
   *   MANAGER          -> all courts (including IsActive = 0)
   *   COURT_MANAGER    -> only courts whose OwnerId = SESSION_CONTEXT('UserId')
   * @param binding carries nothing user-derived; identity comes from the
   * verified SQL session only. Columns are the explicit dbo.Courts columns.
   */
  router.get('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được xem danh sách sân.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    try {
      const rows = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const result = await conn.request().query<ManagerCourt>(`
          SELECT
            CourtId,
            CourtName,
            Address,
            SurfaceType,
            SizeType,
            PricePerHour,
            PricePerThreeHours,
            ImageUrl,
            OwnerId,
            IsActive,
            CreatedAt,
            UpdatedAt
          FROM dbo.Courts
          WHERE
            CONVERT(nvarchar(20), SESSION_CONTEXT(N'Role')) = N'MANAGER'
            OR (
              CONVERT(nvarchar(20), SESSION_CONTEXT(N'Role')) = N'COURT_MANAGER'
              AND OwnerId = TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'UserId'))
            )
          ORDER BY CourtName;
        `);
        return result.recordset;
      });

      const body: ManagerCourtsResponse = {
        courts: rows.map((row) => ({
          ...row,
          PricePerHour: Number(row.PricePerHour ?? 0),
          PricePerThreeHours: Number(row.PricePerThreeHours ?? 0),
          ImageUrl: row.ImageUrl ?? null,
          IsActive: Boolean(row.IsActive),
        })),
        count: rows.length,
      };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      res.status(courtListStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  /**
   * POST /api/manager/courts — create a court through dbo.sp_CreateCourt.
   *
   * The browser sends ONLY editable court fields. @OwnerId is NOT sent: the SP
   * defaults it to the session user (and forces COURT_MANAGER to self), so the
   * creator always becomes the responsible owner — no foreign OwnerId input.
   */
  router.post('/', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được tạo sân.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const validated = validateCourtInput(req.body);
    if (!validated.ok) {
      res.status(400).json({ error: { code: null, message: validated.message } });
      return;
    }

    try {
      const courtId = await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('SessionUserId', sql.UniqueIdentifier, user.userId)
          .input('CourtName', sql.NVarChar(100), validated.input.courtName)
          .input('Address', sql.NVarChar(255), validated.input.address)
          .input('SurfaceType', sql.NVarChar(20), validated.input.surfaceType)
          .input('SizeType', sql.NVarChar(20), validated.input.sizeType)
          .input('PricePerHour', sql.Decimal(12, 0), validated.input.pricePerHour)
          .input('PricePerThreeHours', sql.Decimal(12, 0), validated.input.pricePerThreeHours)
          .input('ImageUrl', sql.NVarChar(500), validated.input.imageUrl)
          .output('CourtId', sql.UniqueIdentifier);
        const result = await r.execute('dbo.sp_CreateCourt');
        return result.output.CourtId as string | undefined;
      });

      if (!courtId) {
        res.status(500).json({ error: { code: null, message: 'Không nhận được kết quả từ hệ thống. Vui lòng thử lại.' } });
        return;
      }

      const body: ManagerCourtCreateResponse = { courtId };
      res.status(201).json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 50070) {
        // Actor/session problem reported by the SP -> re-login required.
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(courtMutationStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  /**
   * PUT /api/manager/courts/:courtId — update a court through dbo.sp_UpdateCourt.
   * The SP re-validates role, SESSION_CONTEXT, ownership (COURT_MANAGER) and
   * price under lock; a foreign-owned court is rejected and left unchanged.
   */
  router.put('/:courtId', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được sửa sân.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const rawCourtId = req.params.courtId;
    if (!isValidGuid(rawCourtId)) {
      res.status(400).json({ error: { code: null, message: 'Mã sân không hợp lệ.' } });
      return;
    }

    const validated = validateCourtInput(req.body);
    if (!validated.ok) {
      res.status(400).json({ error: { code: null, message: validated.message } });
      return;
    }

    try {
      await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('SessionUserId', sql.UniqueIdentifier, user.userId)
          .input('CourtId', sql.UniqueIdentifier, rawCourtId)
          .input('CourtName', sql.NVarChar(100), validated.input.courtName)
          .input('Address', sql.NVarChar(255), validated.input.address)
          .input('SurfaceType', sql.NVarChar(20), validated.input.surfaceType)
          .input('SizeType', sql.NVarChar(20), validated.input.sizeType)
          .input('PricePerHour', sql.Decimal(12, 0), validated.input.pricePerHour)
          .input('PricePerThreeHours', sql.Decimal(12, 0), validated.input.pricePerThreeHours)
          .input('ImageUrl', sql.NVarChar(500), validated.input.imageUrl);
        await r.execute('dbo.sp_UpdateCourt');
      });

      const body: ManagerCourtMutationResponse = { courtId: rawCourtId };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 50080) {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(courtMutationStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  /**
   * POST /api/manager/courts/:courtId/deactivate — soft deactivation through
   * dbo.sp_DeactivateCourt (IsActive = 0). There is NO reactivation in this
   * phase, and NoActivate/reactivation must not be exposed.
   */
  router.post('/:courtId/deactivate', async (req, res) => {
    const user = req.session.user;
    if (!user) {
      res.status(401).json({ error: { code: null, message: 'Chưa đăng nhập.' } });
      return;
    }
    if (user.role !== 'MANAGER' && user.role !== 'COURT_MANAGER') {
      res.status(403).json({ error: { code: null, message: 'Chỉ MANAGER/COURT_MANAGER được ngừng hoạt động sân.' } });
      return;
    }

    const sessionId = req.session.id;
    const contextOk = await sessionDb.verifySessionContext(sessionId, user.userId, user.role);
    if (!contextOk) {
      delete req.session.user;
      res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
      return;
    }

    const rawCourtId = req.params.courtId;
    if (!isValidGuid(rawCourtId)) {
      res.status(400).json({ error: { code: null, message: 'Mã sân không hợp lệ.' } });
      return;
    }

    try {
      await sessionDb.withExistingConnection(sessionId, async (conn) => {
        const r = conn
          .request()
          .input('SessionUserId', sql.UniqueIdentifier, user.userId)
          .input('CourtId', sql.UniqueIdentifier, rawCourtId);
        await r.execute('dbo.sp_DeactivateCourt');
      });

      const body: ManagerCourtMutationResponse = { courtId: rawCourtId };
      res.json(body);
    } catch (err) {
      if (err instanceof Error && err.message === 'No active SQL session connection') {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.' } });
        return;
      }
      const mapped = mapSqlError(err);
      if (mapped.code === 50090) {
        delete req.session.user;
        res.status(401).json({ error: { code: null, message: mapped.message ?? 'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.' } });
        return;
      }
      res.status(courtMutationStatus(mapped)).json({ error: serializeError(mapped) });
    }
  });

  return router;
}