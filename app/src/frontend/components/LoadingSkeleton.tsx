import { BpIcon } from './BpIcon';

interface LoadingSkeletonProps {
  variant?: 'card' | 'list' | 'text' | 'table';
  rows?: number;
  className?: string;
}

/**
 * Shimmer skeleton placeholders (shimmer keyframes come from the locked
 * history screen). `text` renders a single shim block; `list` renders
 * `rows` shim rows; `card` renders a fake card; `table` renders a fake
 * table header + rows.
 */
export function LoadingSkeleton({ variant = 'card', rows = 3, className }: LoadingSkeletonProps) {
  if (variant === 'text') {
    return <div className={['bp-skeleton', 'bp-skeleton--text', className ?? ''].filter(Boolean).join(' ')} />;
  }
  if (variant === 'list') {
    return (
      <div className={['bp-skeleton-list', className ?? ''].filter(Boolean).join(' ')} aria-hidden="true">
        {Array.from({ length: rows }, (_, i) => (
          <div className="bp-skeleton-list__row" key={i}>
            <span className="bp-skeleton bp-skeleton--circle" />
            <span className="bp-skeleton bp-skeleton--line" />
          </div>
        ))}
      </div>
    );
  }
  if (variant === 'table') {
    return (
      <div className={['bp-skeleton-table', className ?? ''].filter(Boolean).join(' ')} aria-hidden="true">
        <div className="bp-skeleton-table__head">
          {Array.from({ length: 5 }, (_, i) => (
            <span className="bp-skeleton bp-skeleton--col" key={i} />
          ))}
        </div>
        {Array.from({ length: rows }, (_, r) => (
          <div className="bp-skeleton-table__row" key={r}>
            {Array.from({ length: 5 }, (_, c) => (
              <span className="bp-skeleton bp-skeleton--col" key={c} />
            ))}
          </div>
        ))}
      </div>
    );
  }
  return (
    <div className={['bp-skeleton ', 'bp-skeleton--card', className ?? ''].filter(Boolean).join(' ')} aria-hidden="true">
      <span className="bp-skeleton bp-skeleton--line" style={{ width: '40%' }} />
      <div className="bp-skeleton--card__row">
        <span className="bp-skeleton bp-skeleton--line" style={{ width: '70%' }} />
        <span className="bp-skeleton bp-skeleton--line" style={{ width: '50%' }} />
      </div>
      <div className="bp-skeleton--card__row">
        <span className="bp-skeleton bp-skeleton--circle" />
        <span className="bp-skeleton bp-skeleton--line" style={{ width: '60%' }} />
      </div>
    </div>
  );
}

/** Inline spinner (used by Button loading + any soft loading affordance). */
export function Spinner({ size = 20, className }: { size?: number; className?: string }) {
  return <BpIcon name="progress_activity" size={size} className={['bp-spinner', className ?? ''].filter(Boolean).join(' ')} />;
}