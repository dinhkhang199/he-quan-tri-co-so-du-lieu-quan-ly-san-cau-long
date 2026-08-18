import { Routes, Route } from 'react-router-dom';
import { HomePage } from './pages/HomePage';

/**
 * Phase 2.0 shell: a single Health landing page.
 * Business screens (login, court search, bookings, ...) ship in Phase 2.1+.
 */
export function App() {
  return (
    <div className="app-shell">
      <Routes>
        <Route path="/" element={<HomePage />} />
      </Routes>
    </div>
  );
}