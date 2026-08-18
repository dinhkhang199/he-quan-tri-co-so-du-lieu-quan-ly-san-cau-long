import { useState, useEffect, useCallback } from 'react';
import { HealthCard } from '../components/HealthCard';

interface HealthApi {
  status: string;
  service: string;
  phase: string;
  db?: 'ok' | 'unreachable' | 'not-configured';
  activeSessionConnections?: number;
  time?: string;
}

export function HomePage() {
  const [health, setHealth] = useState<HealthApi | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await fetch('/api/health');
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setHealth((await res.json()) as HealthApi);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="shell">
      <header className="shell-header">
        <span className="shell-brand">BadmintonPro</span>
        <span className="shell-badge">PHASE 2.0 BOOTSTRAP</span>
      </header>
      <main className="shell-main">
        <HealthCard health={health} error={error} onRetry={() => void load()} />
      </main>
    </div>
  );
}