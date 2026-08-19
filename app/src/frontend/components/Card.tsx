import type { HTMLAttributes, ReactNode } from 'react';

interface CardProps extends HTMLAttributes<HTMLElement> {
  /** Optional card header row (title + optional action). */
  header?: ReactNode;
  /** Optional title shorthand (rendered inside a header). */
  heading?: ReactNode;
  /** Optional action element rendered on the right of a title header. */
  action?: ReactNode;
  /** Remove the default inner padding. */
  flush?: boolean;
  as?: 'section' | 'article' | 'div';
}

/** Surface card with the locked Stitch 18px radius + soft ambient shadow. */
export function Card({
  header,
  heading,
  action,
  flush = false,
  as: Tag = 'section',
  className,
  children,
  ...rest
}: CardProps) {
  const showHeader = header !== undefined || heading !== undefined;
  return (
    <Tag className={['bp-card', flush ? 'bp-card--flush' : '', className ?? ''].filter(Boolean).join(' ')} {...rest}>
      {showHeader ? (
        <div className="bp-card__header">
          <h3 className="bp-card__title">{header ?? heading}</h3>
          {action ? <div className="bp-card__action">{action}</div> : null}
        </div>
      ) : null}
      <div className="bp-card__body">{children}</div>
    </Tag>
  );
}