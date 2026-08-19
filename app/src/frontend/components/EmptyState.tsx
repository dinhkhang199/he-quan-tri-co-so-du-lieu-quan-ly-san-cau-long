import type { ReactNode } from 'react';
import { BpIcon } from './BpIcon';

interface EmptyStateProps {
  icon?: string;
  title: string;
  description?: ReactNode;
  action?: ReactNode;
  className?: string;
}

/** Soft empty-state panel used when a list has no records. */
export function EmptyState({ icon = 'search_off', title, description, action, className }: EmptyStateProps) {
  return (
    <div className={['bp-empty', className ?? ''].filter(Boolean).join(' ')}>
      <div className="bp-empty__icon">
        <BpIcon name={icon} size={40} aria-hidden="true" />
      </div>
      <h3 className="bp-empty__title">{title}</h3>
      {description ? <p className="bp-empty__desc">{description}</p> : null}
      {action ? <div className="bp-empty__action">{action}</div> : null}
    </div>
  );
}