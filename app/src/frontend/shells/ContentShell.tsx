import type { ReactNode } from 'react';

interface ContentShellProps {
  children: ReactNode;
  className?: string;
}

/** Scrollable content area with optional max-width, used inside app shells. */
export function ContentShell({ children, className }: ContentShellProps) {
  return <div className={['bp-content', className ?? ''].filter(Boolean).join(' ')}>{children}</div>;
}