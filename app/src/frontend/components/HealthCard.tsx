interface HealthCardProps {
  health: { status: string; service: string; phase: string; db?: string; activeSessionConnections?: number; time?: string } | null;
  error: string | null;
  onRetry: () => void;
}

/** Minimal Phase 2.0 health/start card. No mock business behavior. */
export function HealthCard({ health, error, onRetry }: HealthCardProps) {
  if (error) {
    return (
      <section className="card card-error">
        <h1 className="card-title">Không thể kết nối server</h1>
        <p className="card-note">{error}</p>
        <button className="btn" onClick={onRetry}>
          Thử lại
        </button>
      </section>
    );
  }

  if (!health) {
    return (
      <section className="card">
        <h1 className="card-title">Đang kiểm tra...</h1>
      </section>
    );
  }

  return (
    <section className="card">
      <h1 className="card-title">Hệ thống đang chạy</h1>
      <dl className="kv">
        <dt>service</dt>
        <dd>{health.service}</dd>
        <dt>status</dt>
        <dd>{health.status.toUpperCase()}</dd>
        <dt>phase</dt>
        <dd>{health.phase}</dd>
        <dt>sql server (shared pool probe)</dt>
        <dd>{health.db ?? 'not-configured'}</dd>
        <dt>session connections</dt>
        <dd>{health.activeSessionConnections ?? 0}</dd>
        <dt>time</dt>
        <dd>{health.time ?? '-'}</dd>
      </dl>
      <button className="btn" onClick={onRetry}>
        Kiểm tra lại
      </button>
    </section>
  );
}