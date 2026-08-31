/* ============================================================
   BadmintonCourtManagement — LOAD TEST: quan sát tranh chấp
   File   : tests/load/observe_contention.sql
   Chạy   : mỘT CỬA SỞ RIÊNG, TRONG LÚC storm đang chạy (sysadmin)
            sqlcmd -S ".\SQLEXPRESS" -E -f 65001 -i tests\load\observe_contention.sql
   Ý nghĩa: chứng minh điểm thắt cổ chai là KHOÁ DÒNG dbo.Courts
            (UPDLOCK/HOLDLOCK trong sp_BookCourt), không phải CPU.
   ============================================================ */

USE BadmintonCourtManagement;
GO
SET NOCOUNT ON;
GO

PRINT N'--- 1. Số connection / session của bcm_app (SessionDb giữ 1 connection / 1 phiên đăng nhập) ---';
SELECT
    login_name,
    COUNT(*)                             AS Sessions,
    SUM(CASE WHEN status = N'running'  THEN 1 ELSE 0 END) AS Running,
    SUM(CASE WHEN status = N'sleeping' THEN 1 ELSE 0 END) AS Sleeping
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name
ORDER BY Sessions DESC;
GO

PRINT N'--- 2. Request đang chờ: wait_type + blocking chain ---';
SELECT TOP (30)
    r.session_id,
    r.status,
    r.wait_type,
    r.wait_time         AS WaitMs,
    r.blocking_session_id,
    r.command,
    OBJECT_NAME(st.objectid, st.dbid) AS ProcName
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.session_id <> @@SPID
ORDER BY r.wait_time DESC;
GO

PRINT N'--- 3. Ai đã gây block? (đếm theo blocking_session_id) ---';
SELECT blocking_session_id, COUNT(*) AS BlockedCount
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0
GROUP BY blocking_session_id
ORDER BY BlockedCount DESC;
GO

PRINT N'--- 4. Khoá đang giữ/đợi trên Courts và Bookings (bằng chứng convoy) ---';
SELECT TOP (40)
    tl.request_session_id AS SessionId,
    OBJECT_NAME(p.object_id) AS TableName,
    tl.resource_type,
    tl.request_mode,
    tl.request_status
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p ON p.hobt_id = tl.resource_associated_entity_id
WHERE tl.resource_database_id = DB_ID()
  AND tl.resource_type IN (N'KEY', N'PAGE', N'OBJECT', N'RID')
ORDER BY CASE tl.request_status WHEN N'WAIT' THEN 0 ELSE 1 END, tl.request_session_id;
GO

PRINT N'--- 5. Wait type tích luỹ quan trọng (LCK_* = khoá, THREADPOOL = hết worker) ---';
SELECT wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE N'LCK_%'
   OR wait_type IN (N'THREADPOOL', N'RESOURCE_SEMAPHORE', N'WRITELOG', N'PAGEIOLATCH_EX', N'ASYNC_NETWORK_IO')
ORDER BY wait_time_ms DESC;
GO

PRINT N'--- 6. Worker thread / connection: giới hạn thực tế của instance ---';
SELECT
    (SELECT max_workers_count FROM sys.dm_os_sys_info)                                  AS MaxWorkers,
    (SELECT SUM(current_workers_count) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE') AS CurrentWorkers,
    (SELECT COUNT(*) FROM sys.dm_exec_connections)                                      AS Connections,
    (SELECT value_in_use FROM sys.configurations WHERE name = N'user connections')       AS ConfigUserConnections,
    (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE' AND is_online = 1) AS OnlineSchedulers;
GO

PRINT N'--- 7. Deadlock đã xảy ra chưa? ---';
SELECT cntr_value AS DeadlocksPerSec_Cumulative
FROM sys.dm_os_performance_counters
WHERE counter_name LIKE N'Number of Deadlocks%'
  AND instance_name = N'_Total';
GO

PRINT N'--- 8. Kết quả nghiệp vụ: bao nhiêu PENDING chồng nhau trên cùng 1 sân/khung giờ ---';
SELECT CourtId, StartTime, EndTime, Status, COUNT(*) AS Rows_
FROM dbo.Bookings
GROUP BY CourtId, StartTime, EndTime, Status
HAVING COUNT(*) > 1
ORDER BY Rows_ DESC;
GO

PRINT N'--- 9. BẤT BIẾN QUAN TRỌNG: không được có 2 BOOKED overlap trên cùng sân ---';
SELECT b1.BookingId AS B1, b2.BookingId AS B2, b1.CourtId, b1.StartTime, b1.EndTime
FROM dbo.Bookings b1
INNER JOIN dbo.Bookings b2
        ON b2.CourtId = b1.CourtId
       AND b2.BookingId <> b1.BookingId
       AND b1.StartTime < b2.EndTime
       AND b1.EndTime   > b2.StartTime
WHERE b1.Status = N'BOOKED' AND b2.Status = N'BOOKED';
PRINT N'    (0 dòng = đúng: khoá UPDLOCK + trigger trg_Bookings_PreventBookedOverlap làm việc)';
GO
