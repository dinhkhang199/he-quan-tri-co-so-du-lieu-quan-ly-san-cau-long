import type { ReactNode } from 'react';

interface PageHeaderProps {
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  className?: string;
}

/** Stitch page header: display-large title, optional subtitle + actions. */
export function PageHeader({ title, subtitle, actions, className }: PageHeaderProps) {
  return (
    <header className={['bp-page-header', className ?? ''].filter(Boolean).join(' ')}>
      <div className="bp-page-header__text">
        <h1 className="bp-page-header__title">{title}</h1>
        {subtitle ? <p className="bp-page-header__subtitle">{subtitle}</p> : null}
      </div>
      {actions ? <div className="bp-page-header__actions">{actions}</div> : null}
    </header>
  );
}